#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=infra/scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'USAGE'
Print the `gh` commands that configure GitHub for CI/CD, filled in from the infra
state file. Prints only; review, fill the <placeholders>, then run them.

Usage:
  print-github-settings.sh --resource-group <name> --pipeline-client-id <guid> [options]

Options:
  -g, --resource-group <name>      Resource group (locates infra/state/<rg>.json)
      --pipeline-client-id <guid>  Client id of the CI/CD app registration (OIDC)
      --environment <name>         GitHub environment (default: dev)
  -s, --state-file <path>          State file (default: infra/state/<rg>.json)
  -h, --help                       Show this help text
USAGE
}

RESOURCE_GROUP=""
PIPELINE_CLIENT_ID=""
GH_ENVIRONMENT="dev"
STATE_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -g|--resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    --pipeline-client-id) PIPELINE_CLIENT_ID="$2"; shift 2 ;;
    --environment) GH_ENVIRONMENT="$2"; shift 2 ;;
    -s|--state-file) STATE_FILE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$RESOURCE_GROUP" || -z "$PIPELINE_CLIENT_ID" ]]; then
  usage
  exit 1
fi
require_command az
require_command jq

STATE_FILE="${STATE_FILE:-$(default_state_file "$SCRIPT_DIR" "$RESOURCE_GROUP")}"
if [[ ! -f "$STATE_FILE" ]]; then
  echo "error: no state file at $STATE_FILE; run the deploy-*.sh scripts first" >&2
  exit 1
fi

state() { jq -r "$1 // \"<missing: run the matching deploy script>\"" "$STATE_FILE"; }

TENANT_ID="$(az account show --query tenantId -o tsv)"
SUBSCRIPTION_ID="$(az account show --query id -o tsv)"

cat <<COMMANDS
# ---- Repository variables (read by CI's publish job, which has no environment) ----
gh variable set AZURE_CLIENT_ID --body "$PIPELINE_CLIENT_ID"
gh variable set AZURE_TENANT_ID --body "$TENANT_ID"
gh variable set AZURE_SUBSCRIPTION_ID --body "$SUBSCRIPTION_ID"
gh variable set ACR_NAME --body "$(state '.services.registry.registryName')"

# ---- '$GH_ENVIRONMENT' environment: deploy targets (scripts/cd.sh) ----
gh variable set RESOURCE_GROUP --env $GH_ENVIRONMENT --body "$RESOURCE_GROUP"
gh variable set KEY_VAULT_NAME --env $GH_ENVIRONMENT --body "$(state '.services.keyVault.keyVaultName')"
gh variable set API_APP_NAME --env $GH_ENVIRONMENT --body "$(state '.services.apiApp.apiAppName')"
gh variable set WEB_APP_NAME --env $GH_ENVIRONMENT --body "$(state '.services.webApp.webAppName')"
gh variable set AZURE_WEB_URL --env $GH_ENVIRONMENT --body "$(state '.services.webApp.webUrl')"

# ---- '$GH_ENVIRONMENT' environment: application settings (deploy/env-contract.json) ----
gh variable set AUTH_MODE --env $GH_ENVIRONMENT --body entra
gh variable set AZURE_TENANT_ID --env $GH_ENVIRONMENT --body "$TENANT_ID"
gh variable set ENTRA_BACKEND_CLIENT_ID --env $GH_ENVIRONMENT --body "<api app registration client id>"
gh variable set ENTRA_BACKEND_APP_ID_URI --env $GH_ENVIRONMENT --body "api://<api app registration client id>"
gh variable set ENTRA_CLIENT_ID --env $GH_ENVIRONMENT --body "<web app registration client id>"
gh variable set ENTRA_TENANT_ID --env $GH_ENVIRONMENT --body "$TENANT_ID"
gh variable set ENTRA_API_SCOPE --env $GH_ENVIRONMENT --body "api://<api app registration client id>/access_as_user"
gh variable set AZURE_AI_FOUNDRY_ENDPOINT --env $GH_ENVIRONMENT --body "<https://unc-resource.openai.azure.com>"
gh variable set AZURE_AI_FOUNDRY_DEPLOYMENT_NAME --env $GH_ENVIRONMENT --body "<chat deployment>"
gh variable set AZURE_STORAGE_ACCOUNT_URL --env $GH_ENVIRONMENT --body "$(state '.services.storage.blobEndpoint')"

# ---- '$GH_ENVIRONMENT' environment secret (cd.sh writes it to Key Vault as database-url) ----
gh secret set DATABASE_URL --env $GH_ENVIRONMENT   # paste: postgresql+psycopg://<login>:<password>@$(state '.services.postgres.serverFqdn'):5432/$(state '.services.postgres.databaseName')?sslmode=require
COMMANDS
