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
2. Provisions infrastructure with Bicep (seeding a public bootstrap image so the
   first run succeeds before your images exist).
3. Builds and pushes the API and web images to ACR.
4. Rolls out the new images with `az containerapp update`.

### Manual deploy (from a workstation)

```bash
az login
az account set --subscription <sub-id>
export SQL_ADMIN_PASSWORD='...'   # not stored anywhere
az deployment sub create \
  --location {{ cookiecutter.azure_location }} \
  --template-file infra/bicep/main.bicep \
  --parameters infra/bicep/parameters/dev.bicepparam \
  --parameters apiImage=mcr.microsoft.com/k8se/quickstart:latest \
               webImage=mcr.microsoft.com/k8se/quickstart:latest
# then build/push images to the created ACR and `az containerapp update`.
```

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
