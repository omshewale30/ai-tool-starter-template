# Runbook

First-time setup of an Azure environment, then day-to-day operations. Infrastructure
is Terraform in `infra/terraform` ([layout](../infra/terraform/README.md)), applied by
an operator; every release is the CD workflow, which never provisions. CD is wired up
for `dev` only ([adding prod](#adding-a-production-environment)).

## 0. Prerequisites

- Terraform ≥ 1.11 (`brew install terraform`), Azure CLI (`az login`), `jq`, and the
  GitHub CLI (`gh auth login`).
- **Owner** (or Contributor + User Access Administrator) on the subscription:
  Terraform creates resource groups and role assignments. Owner grants no access to
  Key Vault *contents* or state blobs; Terraform grants whoever runs it **Key Vault
  Secrets Officer** and **Storage Blob Data Contributor** on the state account, and
  waits for the grants to apply.
- The GitHub repository for this project, ideally in the `FO-AI` organization.

```bash
az account set --subscription <subscription id>
export ARM_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"   # every Terraform run
```

Terraform signs in with your `az login`. Each root under `infra/terraform` keeps its
state in the bootstrap storage account; `terraform output` in a root prints its values.

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

Roles are granted by Terraform once you set its **object id** (the service
principal's, not the app registration's) as `deploy_principal_id` in
`infra/terraform/envs/shared/terraform.tfvars` (AcrPush and Contributor on the registry,
for `az acr build`) and in each
`envs/<env>/terraform.tfvars` (Contributor on the resource group for container app
updates, Key Vault Secrets Officer for `database-url`).

```bash
az ad sp show --id <CI/CD app client id> --query id -o tsv
```

## 3. Azure resources (Terraform)

If more than one person will run Terraform, create an Entra group for them first and
set it as `state_contributor_principal_ids` (bootstrap) and `operator_principal_ids`
(each env); otherwise access follows whoever applied last.

Once per subscription, the state backend (local state; also registers the resource
providers the stack uses):

```bash
cd infra/terraform/bootstrap
terraform init && terraform apply
terraform output -raw backend_config > ../backend.hcl   # commit backend.hcl
```

Then the shared registry, then each environment (`make tf-init tf-plan tf-apply
ENV=<root>` does the same from the repo root):

```bash
cd ../envs/shared
terraform init -backend-config=../../backend.hcl
terraform plan -out=tfplan && terraform apply tfplan      # ACR

cd ../dev
terraform init -backend-config=../../backend.hcl
terraform plan -out=tfplan && terraform apply tfplan      # everything else (~10 min)
```

`envs/dev` creates the resource group, managed identity, Log Analytics + Application
Insights, Key Vault, Storage, PostgreSQL{% if cookiecutter.enable_ai_search == "yes" %}, AI Search{% endif %},
the Container Apps environment, and both apps. Terraform generates the Postgres admin
password (it never enters state) and stores it in Key Vault as `postgres-admin-password`,
along with a ready `database-url`.

The apps start on a placeholder image and get real images from the first CD run.
From then on CD owns their image and env: Terraform ignores both, so re-applying is
always safe. Change everything else (scale, probes, secrets, ingress) in Terraform.

Then:
- add `<web url>/auth` (`terraform output web_url`) to the web app registration's SPA
  redirect URIs;
- request **Cognitive Services OpenAI User** on UNC's Azure OpenAI for the app
  identity (`terraform output identity`, `principal_id`); see [ai.md](ai.md).

## 4. GitHub configuration

```bash
infra/scripts/print-github-settings.sh --environment dev --pipeline-client-id <CI/CD app client id>
```

prints every `gh variable set` / `gh secret set` command, filled in from the Terraform
outputs. Fill the `<placeholders>` and run them. Summary:

| Where | Name | Notes |
| --- | --- | --- |
| Repository variables | `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` | The CI/CD identity; `publish` runs outside the environment and can only read these |
| Repository variable | `ACR_NAME` | Registry name (not the login server) |
| `dev` variables | `RESOURCE_GROUP`, `KEY_VAULT_NAME`, `API_APP_NAME`, `WEB_APP_NAME`, `AZURE_WEB_URL`, optional `WEB_URL` (custom domain) | Deploy targets |
| `dev` variables | `AUTH_MODE`=`entra`, `AZURE_TENANT_ID`, `ENTRA_BACKEND_CLIENT_ID`, `ENTRA_BACKEND_APP_ID_URI`, `ENTRA_CLIENT_ID`, `ENTRA_TENANT_ID`, `ENTRA_API_SCOPE`, `AZURE_AI_FOUNDRY_*`, … | Application settings; the full list is `deploy/env-contract.json` |
| `dev` secret | `DATABASE_URL` | Copied from Key Vault `database-url` (the printed command does it); CD writes it back on every deploy |

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
| Rotate the DB password | Bump `postgres_password_version` in the env's tfvars and apply; copy the new `database-url` to the `DATABASE_URL` secret (step 4's command); redeploy |
| API logs | `az containerapp logs show -g rg-{{ cookiecutter.resource_prefix }}-dev -n <api app> --follow` |
| Traces, failures, AI usage | Application Insights → *Transaction search*, *Failures*; spans named `ai.*` carry token usage |
| Who did what | `/admin` in the app (audit events) |
| Scale / size | `apps`, `postgres_sku_name`, … in `infra/terraform/envs/<env>/terraform.tfvars`, then plan and apply (no redeploy needed) |
| Infra drift check | `make tf-plan ENV=dev` should show no changes |

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
| `terraform init`: 403 on the state blob | You lack Storage Blob Data Contributor on the state account. Join the operators group set in `bootstrap/terraform.tfvars`, or have an Owner grant you the role on it |
| `terraform apply`: 403 from Key Vault | Role assignment still propagating; re-run apply |
| `terraform apply`: "MissingSubscriptionRegistration" | Provider not registered; apply `infra/terraform/bootstrap` (it registers them) |
| CD: "the app declares no secret database-url" | API app changed outside Terraform; `terraform apply` in `envs/<env>` restores it |
| CD: "must have internal ingress" | API ingress changed outside Terraform; `terraform apply` restores it |
| Site health: `auth.configured == true` failed | `AZURE_TENANT_ID` / `ENTRA_BACKEND_*` not set in `dev` |
| Site health: `ai.configured == true` failed | `AZURE_AI_FOUNDRY_ENDPOINT` / `..._DEPLOYMENT_NAME` not set |
| Every API call 401 after sign-in | API registration issues v1 tokens (`requestedAccessTokenVersion` must be 2) or audience mismatch |
| AADSTS50011 redirect mismatch | `<origin>/auth` not registered as a **SPA** redirect URI |
| AI calls 502, log says 401/403 | App identity lacks Cognitive Services OpenAI User on UNC's resource |
| Revision unhealthy right after deploy | Migrations failed or DB unreachable: check API logs (`alembic upgrade head` runs at start) |

## Adding a production environment

`infra/terraform/envs/prod` already exists, sized for production in its
`terraform.tfvars` (General Purpose Postgres with geo-redundant backup, ZRS storage,
two replicas per app, Key Vault purge protection). Review it, then:

1. `make tf-init tf-plan tf-apply ENV=prod`; it pulls from the same shared registry.
2. Create a `prod` GitHub environment (with required reviewers) and run
   `print-github-settings.sh --environment prod`.
3. Add a federated credential for `environment:prod`.
4. Add a second job to `.github/workflows/cd.yml` that calls the same reusable
   workflow with `environment: prod`, `needs: deploy`, so it promotes the digests
   `dev` just verified. First parameterize `scripts/cd.sh`, which currently
   hard-codes `dev` (the `ENVIRONMENT` it sets and the health check that expects it),
   e.g. from a `DEPLOY_ENVIRONMENT` variable set per GitHub environment.
