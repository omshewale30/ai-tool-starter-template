# Runbook

First-time setup of an Azure environment, then day-to-day operations. Resources are
created once by hand with `infra/scripts/deploy-*.sh`; every later release is the CD
workflow. Only a `dev` environment is wired up ([adding prod](#adding-a-production-environment)).

## 0. Prerequisites

- Azure CLI (`az login`), `jq`, and the GitHub CLI (`gh auth login`).
- A resource group, and **Owner** (or Contributor + User Access Administrator) on it:
  the scripts create role assignments.
- The GitHub repository for this project, ideally in the `FO-AI` organization.

```bash
export RG=rg-{{ cookiecutter.resource_prefix }}-dev
az group create -n "$RG" -l {{ cookiecutter.azure_location }}   # if it doesn't exist
```

Every script takes `-g <resource-group>` and remembers its outputs in
`infra/state/<resource-group>.json` (git-ignored), so later scripts find earlier
resources without arguments. `-h` prints each script's options.

## 1. App registrations

Created by hand in Entra ID (or requested from UNC ITS). Two registrations:

**API** (`{{ cookiecutter.project_name }} API`)
- *Expose an API*: Application ID URI `api://<api client id>`; scope
  `access_as_user` (admins and users can consent).
- *Manifest*: `"requestedAccessTokenVersion": 2`. Without it Entra issues v1 tokens
  whose issuer the API rejects, and every call returns 401.
- *App roles*: `admin` (value `admin`, allowed member type Users/Groups). Assign it
  to admins under *Enterprise applications → Users and groups*. App roles are
  preferred over group claims: users in more than 200 groups get no `groups` claim
  (overage), so group checks fail silently. `ADMIN_GROUP_ID` remains as a fallback.

**Web** (`{{ cookiecutter.project_name }}`)
- *Authentication*: platform **Single-page application** with redirect URIs
  `https://<web url>/auth` and `http://localhost:3000/auth`. No secret.
- *API permissions*: the API's `access_as_user` (delegated); grant admin consent,
  or pre-authorize the web client id on the API registration.

You need: tenant id, API client id, web client id.

## 2. CI/CD identity (GitHub OIDC)

One app registration (or user-assigned identity) that GitHub Actions signs in as. No
secrets: two **federated credentials** for this repository:

| Used by | Subject |
| --- | --- |
| CI `publish` job (no environment) | `repo:<org>/<repo>:ref:refs/heads/main` |
| CD `deploy` job (`dev` environment) | `repo:<org>/<repo>:environment:dev` |

If the repository uses **immutable subject claims** (FO-AI repos do), the subjects
take the form `repo:<org>@<org-id>/<repo>@<repo-id>:ref:refs/heads/main` (and
`...:environment:dev`); with the plain form the first sign-in fails with a confusing
"no matching federated identity" error. Copy the exact subject from that error if
unsure.

Roles: **Contributor** on the resource group (container app updates). AcrPush and
Key Vault Secrets Officer are granted by the scripts below when you pass its
**object id** as `DEPLOY_PRINCIPAL_ID`.

```bash
export DEPLOY_PRINCIPAL_ID=<object id of the CI/CD service principal>
az role assignment create --assignee-object-id "$DEPLOY_PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal --role Contributor \
  --scope "$(az group show -n "$RG" --query id -o tsv)"
```

## 3. Azure resources (once, in order)

```bash
cd infra/scripts
./deploy-identity.sh -g "$RG"            # user-assigned identity for both apps
./deploy-observability.sh -g "$RG"       # Log Analytics + Application Insights
./deploy-registry.sh -g "$RG"            # ACR (AcrPull for apps, AcrPush for CI/CD)
./deploy-storage.sh -g "$RG"             # Blob storage
PG_ADMIN_PASSWORD=<16+ letters/digits> ./deploy-postgres.sh -g "$RG"
./deploy-key-vault.sh -g "$RG"           # seeds the App Insights connection string
{%- if cookiecutter.enable_ai_search == "yes" %}
./deploy-search.sh -g "$RG"              # optional now; see docs/rag.md
{%- endif %}
./deploy-container-apps-env.sh -g "$RG"
DATABASE_URL='postgresql+psycopg://<login>:<password>@<server>.postgres.database.azure.com:5432/appdb?sslmode=require' \
  ./deploy-api-app.sh -g "$RG"            # internal ingress; seeds Key Vault database-url
./deploy-web-app.sh -g "$RG"              # public ingress; prints the web URL
```

The apps start on a placeholder image. They get real images from the first CD run.
Re-running `deploy-api-app.sh`/`deploy-web-app.sh` is refused once an app exists
(CD owns image and env from then on); pass `--recreate` only if you mean it.

Then:
- add `<web url>/auth` to the web app registration's SPA redirect URIs;
- request **Cognitive Services OpenAI User** on UNC's Azure OpenAI for the app
  identity (`identity.principalId` in the state file); see [ai.md](ai.md).

## 4. GitHub configuration

```bash
./print-github-settings.sh -g "$RG" --pipeline-client-id <CI/CD app client id>
```

prints every `gh variable set` / `gh secret set` command, filled in from the state
file. Fill the `<placeholders>` and run them. Summary:

| Where | Name | Notes |
| --- | --- | --- |
| Repository variables | `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` | The CI/CD identity; `publish` runs outside the environment and can only read these |
| Repository variable | `ACR_NAME` | Registry name (not the login server) |
| `dev` variables | `RESOURCE_GROUP`, `KEY_VAULT_NAME`, `API_APP_NAME`, `WEB_APP_NAME`, `AZURE_WEB_URL`, optional `WEB_URL` (custom domain) | Deploy targets |
| `dev` variables | `AUTH_MODE`=`entra`, `AZURE_TENANT_ID`, `ENTRA_BACKEND_CLIENT_ID`, `ENTRA_BACKEND_APP_ID_URI`, `ENTRA_CLIENT_ID`, `ENTRA_TENANT_ID`, `ENTRA_API_SCOPE`, `AZURE_AI_FOUNDRY_*`, … | Application settings; the full list is `deploy/env-contract.json` |
| `dev` secret | `DATABASE_URL` | Written to Key Vault `database-url` on every deploy |

`AZURE_CLIENT_ID` the repository variable is the CI/CD identity; the API's own
`AZURE_CLIENT_ID` (its managed identity) is set by infra and never read from GitHub.

Also:
- **Environment `dev`**: *Deployment branches* → `main` only.
- **Branch protection on `main`**: require the `verify` check (only that one; adding
  checks then needs no rule change).

## 5. First deploy

Push to `main` (or re-run CI on it). CI passes → `publish` builds both images in ACR
and smoke-tests them → CD (`.github/workflows/cd.yml`) runs `scripts/cd.sh`:

1. validates every setting against `deploy/env-contract.json` (nothing changes yet);
2. checks both apps (single revision, `minReplicas ≥ 1`, managed-identity pull,
   internal API ingress) and derives `BACKEND_ORIGIN` from the API's internal FQDN;
3. rechecks that the commit is still `main`, syncs `database-url` to Key Vault;
4. rolls out the API, then the web, each gated on revision health;
5. checks `<web>/api/health` end to end (database, auth, AI configured) and `/`;
6. on any failure, rolls back web then API to the previous images and env.

The job summary shows the deployed digests and the outcome.

## Operations

| Task | How |
| --- | --- |
| Redeploy current `main` | Actions → CD → *Run workflow* |
| Roll back a bad release | Revert the commit on `main`; CD deploys the revert. (Failed deploys roll back automatically.) |
| Remove a hand-set container env var | CD → *Run workflow* with **allow-prune** |
| Change a setting | Update the GitHub variable/secret, then redeploy |
| Rotate the DB password | Change it on the server, update the `DATABASE_URL` secret, redeploy |
| API logs | `az containerapp logs show -g $RG -n <api app> --follow` |
| Traces, failures, AI usage | Application Insights → *Transaction search*, *Failures*; spans named `ai.*` carry token usage |
| Who did what | `/admin` in the app (audit events) |
| Scale | `minReplicas`/`maxReplicas`, `cpu`, `memory` in `infra/bicep/services/*-app.bicep`, then `--recreate` and redeploy |

Useful Log Analytics query (AI calls by model, last day):

```kusto
AppDependencies
| where TimeGenerated > ago(1d) and Name startswith "ai."
| summarize calls = count(), p95_ms = percentile(DurationMs, 95),
    output_tokens = sum(toint(Properties["gen_ai.usage.output_tokens"]))
    by Name, tostring(Properties["gen_ai.response.model"])
```

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| `publish`: "Set AZURE_TENANT_ID as a repository or organization variable" | Repository variables missing (environment ones aren't visible to `publish`) |
| `azure/login`: no matching federated identity | Subject mismatch; see the immutable-claims note in step 2 |
| CD: "would be removed: X" | A variable on the app isn't in the contract; add it, or run CD with allow-prune |
| CD: "the app declares no secret database-url" | API app created without the Key Vault reference; `deploy-api-app.sh --recreate` |
| CD: "must have internal ingress" | API app exposed publicly; recreate it with `deploy-api-app.sh --recreate` |
| Site health: `auth.configured == true` failed | `AZURE_TENANT_ID` / `ENTRA_BACKEND_*` not set in `dev` |
| Site health: `ai.configured == true` failed | `AZURE_AI_FOUNDRY_ENDPOINT` / `..._DEPLOYMENT_NAME` not set |
| Every API call 401 after sign-in | API registration issues v1 tokens (`requestedAccessTokenVersion` must be 2) or audience mismatch |
| AADSTS50011 redirect mismatch | `<origin>/auth` not registered as a **SPA** redirect URI |
| AI calls 502, log says 401/403 | App identity lacks Cognitive Services OpenAI User on UNC's resource |
| Revision unhealthy right after deploy | Migrations failed or DB unreachable: check API logs (`alembic upgrade head` runs at start) |

## Adding a production environment

1. Create a separate resource group and repeat steps 3–4 with `-e prod` and a
   `prod` GitHub environment (with required reviewers).
2. Add a federated credential for `environment:prod`.
3. Add a second job to `.github/workflows/cd.yml` that calls the same reusable
   workflow with `environment: prod`, `needs: deploy`, so it promotes the digests
   `dev` just verified. First parameterize `scripts/cd.sh`, which currently
   hard-codes `dev` (the `ENVIRONMENT` it sets and the health check that expects it),
   e.g. from a `DEPLOY_ENVIRONMENT` variable set per GitHub environment.
