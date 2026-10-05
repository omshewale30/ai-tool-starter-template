#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=infra/scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'USAGE'
Create the API Container App (internal ingress) with a bootstrap image.

Usage:
  [DATABASE_URL=<url>] deploy-api-app.sh --resource-group <name> [options]

After this, scripts/cd.sh (the CD workflow) owns the image and application env.

Options:
  -g, --resource-group <name>        Existing resource group name (required)
  -e, --environment <name>           Environment name used in naming/tags (default: dev)
  -l, --location <region>            Azure region (default: resource group location)
  -p, --resource-prefix <pref>       Resource prefix (default: {{ cookiecutter.resource_prefix }})
      --image <ref>                  Bootstrap image (default: Container Apps quickstart)
      --environment-id <id>          Container Apps env id (default: state containerAppsEnv.environmentId)
      --identity-id <id>             User-assigned identity id (default: state identity.id)
      --identity-client-id <id>      User-assigned identity client id (default: state identity.clientId)
      --registry-server <server>     ACR login server (default: state registry.loginServer)
      --key-vault-name <name>        Key Vault name (default: state keyVault.keyVaultName)
      --key-vault-uri <uri>          Key Vault URI (default: state keyVault.keyVaultUri)
      --recreate                     Re-run even though the app exists (resets image and env)
  -s, --state-file <path>            Local state file path (default: infra/state/<rg>.json)
      --deployment-name <name>       Override ARM deployment name
  -h, --help                         Show this help text

The app reads DATABASE_URL from the Key Vault secret `database-url`, which must exist
before the app is created. If it does not, this script seeds it from the DATABASE_URL
environment variable (scripts/cd.sh keeps it in sync from then on).
USAGE
}

RESOURCE_GROUP=""
ENVIRONMENT_NAME="dev"
LOCATION=""
RESOURCE_PREFIX="{{ cookiecutter.resource_prefix }}"
IMAGE=""
ENVIRONMENT_ID=""
IDENTITY_ID=""
IDENTITY_CLIENT_ID=""
REGISTRY_SERVER=""
KEY_VAULT_NAME=""
KEY_VAULT_URI=""
RECREATE="false"
STATE_FILE=""
DEPLOYMENT_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -g|--resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    -e|--environment) ENVIRONMENT_NAME="$2"; shift 2 ;;
    -l|--location) LOCATION="$2"; shift 2 ;;
    -p|--resource-prefix) RESOURCE_PREFIX="$2"; shift 2 ;;
    --image) IMAGE="$2"; shift 2 ;;
    --environment-id) ENVIRONMENT_ID="$2"; shift 2 ;;
    --identity-id) IDENTITY_ID="$2"; shift 2 ;;
    --identity-client-id) IDENTITY_CLIENT_ID="$2"; shift 2 ;;
    --registry-server) REGISTRY_SERVER="$2"; shift 2 ;;
    --key-vault-name) KEY_VAULT_NAME="$2"; shift 2 ;;
    --key-vault-uri) KEY_VAULT_URI="$2"; shift 2 ;;
    --recreate) RECREATE="true"; shift ;;
    -s|--state-file) STATE_FILE="$2"; shift 2 ;;
    --deployment-name) DEPLOYMENT_NAME="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$RESOURCE_GROUP" ]]; then
  echo "error: --resource-group is required" >&2
  usage
  exit 1
fi

require_command az
require_command jq

if [[ -z "$STATE_FILE" ]]; then
  STATE_FILE="$(default_state_file "$SCRIPT_DIR" "$RESOURCE_GROUP")"
fi
ensure_state_file "$STATE_FILE"

APP_NAME="ca-${RESOURCE_PREFIX}-${ENVIRONMENT_NAME}-api"
refuse_if_app_exists "$APP_NAME" "$RESOURCE_GROUP" "$RECREATE"

ENVIRONMENT_ID="$(resolve_required_value "$ENVIRONMENT_ID" "$STATE_FILE" '.services.containerAppsEnv.environmentId' '--environment-id')"
IDENTITY_ID="$(resolve_required_value "$IDENTITY_ID" "$STATE_FILE" '.services.identity.id' '--identity-id')"
IDENTITY_CLIENT_ID="$(resolve_required_value "$IDENTITY_CLIENT_ID" "$STATE_FILE" '.services.identity.clientId' '--identity-client-id')"
REGISTRY_SERVER="$(resolve_required_value "$REGISTRY_SERVER" "$STATE_FILE" '.services.registry.loginServer' '--registry-server')"
KEY_VAULT_NAME="$(resolve_required_value "$KEY_VAULT_NAME" "$STATE_FILE" '.services.keyVault.keyVaultName' '--key-vault-name')"
KEY_VAULT_URI="$(resolve_required_value "$KEY_VAULT_URI" "$STATE_FILE" '.services.keyVault.keyVaultUri' '--key-vault-uri')"
LOCATION="$(resolve_location "$RESOURCE_GROUP" "$LOCATION")"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-$(new_deployment_name api-app "$ENVIRONMENT_NAME")}"

# A Key Vault reference to a missing secret fails app creation, so seed database-url
# once. Through a private file, never argv.
if ! az keyvault secret show --vault-name "$KEY_VAULT_NAME" --name database-url --output none 2>/dev/null; then
  if [[ -z "${DATABASE_URL:-}" ]]; then
    echo "error: Key Vault secret database-url does not exist. Set DATABASE_URL (see" >&2
    echo "       deploy-postgres.sh output) and re-run; CD keeps it in sync afterwards." >&2
    exit 1
  fi
  secret_file="$(mktemp)"
  trap 'rm -f "$secret_file"' EXIT
  chmod 600 "$secret_file"
  printf '%s' "$DATABASE_URL" >"$secret_file"
  az keyvault secret set --vault-name "$KEY_VAULT_NAME" --name database-url --file "$secret_file" --output none
  echo "seeded Key Vault secret database-url"
fi

ENABLE_APP_INSIGHTS="false"
if az keyvault secret show --vault-name "$KEY_VAULT_NAME" --name appinsights-connection-string --output none 2>/dev/null; then
  ENABLE_APP_INSIGHTS="true"
fi

image_args=()
[[ -n "$IMAGE" ]] && image_args=(image="$IMAGE")

deployment_json="$(az deployment group create \
  --name "$DEPLOYMENT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --template-file "$SCRIPT_DIR/../bicep/services/api-app.bicep" \
  --parameters \
    resourcePrefix="$RESOURCE_PREFIX" \
    environmentName="$ENVIRONMENT_NAME" \
    location="$LOCATION" \
    environmentId="$ENVIRONMENT_ID" \
    userAssignedIdentityId="$IDENTITY_ID" \
    userAssignedIdentityClientId="$IDENTITY_CLIENT_ID" \
    registryServer="$REGISTRY_SERVER" \
    keyVaultUri="$KEY_VAULT_URI" \
    enableAppInsights="$ENABLE_APP_INSIGHTS" \
    ${image_args[@]+"${image_args[@]}"} \
  -o json)"

save_service_outputs "$STATE_FILE" "apiApp" "$RESOURCE_GROUP" "$ENVIRONMENT_NAME" "$RESOURCE_PREFIX" "$deployment_json"

echo "api app created"
echo "state file: $STATE_FILE"
print_outputs "$deployment_json"
echo
echo "Next: deploy-web-app.sh, then set the GitHub variables and run CD (docs/runbook.md)."
