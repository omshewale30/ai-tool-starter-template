# Runbook

Operational procedures for {{ cookiecutter.project_name }}.

## Deploy

### Prerequisites (one-time)

1. Create the two Entra app registrations (frontend SPA, backend API) — see
   [security.md](security.md) and the auth troubleshooting section below.
2. Create an Entra app registration for the deploy pipeline and configure a
   **federated credential** for GitHub OIDC (subject
   `repo:<org>/<repo>:environment:dev`). Grant it `Contributor` (+ `User Access
   Administrator` for role assignments) on the target subscription.
3. Configure GitHub repository **secrets** and **variables**:

   | Kind | Name | Example |
   | --- | --- | --- |
   | secret | `AZURE_CLIENT_ID` | pipeline app client id |
   | secret | `AZURE_TENANT_ID` | tenant id |
   | secret | `AZURE_SUBSCRIPTION_ID` | subscription id |
   | secret | `SQL_ADMIN_PASSWORD` | strong password |
   | var | `AZURE_LOCATION` | `{{ cookiecutter.azure_location }}` |
   | var | `ADMIN_GROUP_ID` | admin group object id |
   | var | `ENTRA_FRONTEND_CLIENT_ID` | SPA client id |
   | var | `ENTRA_BACKEND_APP_ID_URI` | `{{ cookiecutter.backend_app_id_uri }}` |
   | var | `AZURE_AI_FOUNDRY_ENDPOINT` | Foundry endpoint |

### Automated deploy

Push to `main` or run the **Deploy (dev)** workflow manually. It:

1. Logs in to Azure via OIDC.
2. Provisions infrastructure with Bicep.
3. Builds and pushes the API and web images to ACR.
4. Rolls out the new images with `az containerapp update`.

> Note: the current workflow still uses `infra/bicep/main.bicep` (legacy
> monolithic path). The recommended operator workflow is the new per-service
> scripts below.

### Manual deploy (per service into an existing RG)

Create the resource group manually first, then deploy one service per run.
Scripts never create resource groups.

Each script:

- uses `az deployment group create`
- deploys exactly one service entrypoint in `infra/bicep/services`
- writes outputs to `infra/state/<resource-group>.json` for explicit dependency chaining

#### Deployment order (recommended)

1. `identity`: foundation for RBAC assignments used by other services.
2. `observability`: Log Analytics/App Insights needed by Key Vault seed + CA env.
3. `registry`: needs identity principal id.
4. `storage`: needs identity principal id.
5. `postgres` (currently backed by the Azure SQL module): needs Entra admin object id (typically identity principal id).
6. `key-vault`: needs identity principal id; optionally seeds SQL/App Insights secrets.
7. `container-apps-env`: needs Log Analytics workspace name.
8. `search` (optional): needs identity principal id.
9. `api-app`: needs env, identity, registry, storage, database, and key vault outputs.
10. `web-app`: needs env, identity, and registry outputs.

#### Exact commands for `rg-nimbus`

```bash
az login
az account set --subscription <sub-id>
export SQL_ADMIN_PASSWORD='...'
export API_IMAGE='REPLACE_ME.azurecr.io/{{ cookiecutter.project_slug }}-api:<tag>'
export WEB_IMAGE='REPLACE_ME.azurecr.io/{{ cookiecutter.project_slug }}-web:<tag>'
export AZURE_AI_FOUNDRY_ENDPOINT='https://<foundry-resource>.openai.azure.com/'

cd infra/scripts

./deploy-identity.sh -g rg-nimbus -e dev -l {{ cookiecutter.azure_location }}
./deploy-observability.sh -g rg-nimbus -e dev -l {{ cookiecutter.azure_location }}
./deploy-registry.sh -g rg-nimbus -e dev -l {{ cookiecutter.azure_location }}
./deploy-storage.sh -g rg-nimbus -e dev -l {{ cookiecutter.azure_location }}
./deploy-postgres.sh -g rg-nimbus -e dev -l {{ cookiecutter.azure_location }} --sql-admin-password "$SQL_ADMIN_PASSWORD"
./deploy-key-vault.sh -g rg-nimbus -e dev -l {{ cookiecutter.azure_location }} --sql-admin-password "$SQL_ADMIN_PASSWORD"
./deploy-container-apps-env.sh -g rg-nimbus -e dev -l {{ cookiecutter.azure_location }}

# Optional search service:
./deploy-search.sh -g rg-nimbus -e dev -l {{ cookiecutter.azure_location }}

./deploy-api-app.sh -g rg-nimbus -e dev -l {{ cookiecutter.azure_location }} \
  --image "$API_IMAGE" \
  --foundry-endpoint "$AZURE_AI_FOUNDRY_ENDPOINT"
./deploy-web-app.sh -g rg-nimbus -e dev -l {{ cookiecutter.azure_location }} \
  --image "$WEB_IMAGE"
```

If needed, pass explicit dependency overrides to any script (`--help`) instead of
state-file defaults.

Apply database migrations after the first deploy (from a machine that can reach
Azure SQL, or a one-off job):

```bash
alembic upgrade head
```

## Rotate secrets

- **SQL admin password**: update the GitHub secret `SQL_ADMIN_PASSWORD`, then
  re-run the deploy (Bicep updates the server and the Key Vault seed secret). Or
  rotate directly with `az sql server update` and update Key Vault.
- **Key Vault secrets**: `az keyvault secret set --vault-name <kv> --name <n>
  --value <v>`. Container Apps pick up new versions on the next revision; restart
  with `az containerapp revision restart` if needed.
- **Entra client secrets**: prefer managed identity / federated credentials so
  there are no client secrets to rotate. If one exists, roll it in Entra and
  update the corresponding Key Vault secret.

## Inspect logs

```bash
# Live tail from a container app
az containerapp logs show -n <app-name> -g <rg> --follow

# Structured queries in Log Analytics (App Insights)
# Portal > Logs, or:
az monitor log-analytics query -w <workspace-id> \
  --analytics-query "ContainerAppConsoleLogs_CL | where Log_s has 'correlation_id' | take 50"
```

Every log line and error response carries a `correlationId` — use it to trace a
single request end to end.

## Troubleshoot auth issues

| Symptom | Likely cause / fix |
| --- | --- |
| `401 unauthorized` for all calls | Token audience/issuer mismatch. Confirm `ENTRA_BACKEND_APP_ID_URI` and `AZURE_TENANT_ID`, and that the SPA requests the correct scope. |
| `401` intermittently | Clock skew or expired token; MSAL should refresh. Check `jwt_leeway_seconds`. |
| `403 forbidden` on admin routes | User lacks the `admin` role or `ADMIN_GROUP_ID` membership. |
| Works locally, fails deployed | You were running with `AUTH_MODE=disabled`. Test with `AUTH_MODE=entra` and a real token. |
| Login loop / redirect error | `NEXT_PUBLIC_ENTRA_REDIRECT_URI` must be registered as a redirect URI on the SPA app registration. |

Decode a token at <https://jwt.ms> to inspect `aud`, `iss`, `roles`, `groups`.

## Troubleshoot Foundry calls

| Symptom | Likely cause / fix |
| --- | --- |
| `502 upstream_error` from `/chat` | Foundry call failed. Check backend logs for the wrapped exception. |
| `AZURE_AI_FOUNDRY_ENDPOINT is not configured` | Set the endpoint and switch `AI_PROVIDER=foundry`. |
| `403` from Foundry | The managed identity lacks a role on the AI resource, or the wrong `AZURE_CLIENT_ID` is set. Grant `Cognitive Services User`. |
| SDK / signature errors | Confirm the installed `openai`/`azure-ai-*` version matches `foundry_provider._invoke_model`; update that one adapter method. |
| Deployment name errors | `AZURE_AI_FOUNDRY_DEPLOYMENT_NAME` must match a real model deployment. |

To bisect, set `AI_PROVIDER=mock` — if `/chat` then works, the issue is isolated
to the Foundry integration.

## Onboard a new developer

1. Install prerequisites (Docker, Node 20 LTS/22 LTS, Python 3.11+). See
   [local-development.md](local-development.md).
2. `cp .env.example .env` and `make dev`.
3. Open http://localhost:3000 (auth disabled, mock AI — no Azure needed).
4. Grant Azure access only when they need to deploy or use real Foundry.
