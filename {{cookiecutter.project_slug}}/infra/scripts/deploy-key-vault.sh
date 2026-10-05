#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=infra/scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'USAGE'
Deploy Key Vault + RBAC assignment + optional seed secrets.

Usage:
  deploy-key-vault.sh --resource-group <name> [options]

Options:
  -g, --resource-group <name>              Existing resource group name (required)
  -e, --environment <name>                 Environment name used in naming/tags (default: dev)
  -l, --location <region>                  Azure region (default: resource group location)
  -p, --resource-prefix <pref>             Resource prefix (default: {{ cookiecutter.resource_prefix }})
      --app-principal-id <id>              Managed identity principal id (defaults from state identity.principalId)
      --appinsights-connection-string <v>  Optional seed secret value (defaults from state observability.appInsightsConnectionString)
      --pipeline-principal-id <id>        CD pipeline identity object id; granted Key Vault Secrets
                                           Officer so scripts/cd.sh can write database-url
                                           (or DEPLOY_PRINCIPAL_ID env var)
  -s, --state-file <path>                  Local state file path (default: infra/state/<rg>.json)
      --deployment-name <name>             Override ARM deployment name
  -h, --help                               Show this help text
USAGE
}

RESOURCE_GROUP=""
ENVIRONMENT_NAME="dev"
LOCATION=""
RESOURCE_PREFIX="{{ cookiecutter.resource_prefix }}"
APP_PRINCIPAL_ID=""
APPINSIGHTS_CONNECTION_STRING=""
PIPELINE_PRINCIPAL_ID="${DEPLOY_PRINCIPAL_ID:-}"
STATE_FILE=""
DEPLOYMENT_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -g|--resource-group)
      RESOURCE_GROUP="$2"
      shift 2
      ;;
    -e|--environment)
      ENVIRONMENT_NAME="$2"
      shift 2
      ;;
    -l|--location)
      LOCATION="$2"
      shift 2
      ;;
    -p|--resource-prefix)
      RESOURCE_PREFIX="$2"
      shift 2
      ;;
    --app-principal-id)
      APP_PRINCIPAL_ID="$2"
      shift 2
      ;;
    --appinsights-connection-string)
      APPINSIGHTS_CONNECTION_STRING="$2"
      shift 2
      ;;
    --pipeline-principal-id)
      PIPELINE_PRINCIPAL_ID="$2"
      shift 2
      ;;
    -s|--state-file)
      STATE_FILE="$2"
      shift 2
      ;;
    --deployment-name)
      DEPLOYMENT_NAME="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage
      exit 1
      ;;
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

APP_PRINCIPAL_ID="$(resolve_required_value "$APP_PRINCIPAL_ID" "$STATE_FILE" '.services.identity.principalId' '--app-principal-id')"
APPINSIGHTS_CONNECTION_STRING="$(resolve_optional_value "$APPINSIGHTS_CONNECTION_STRING" "$STATE_FILE" '.services.observability.appInsightsConnectionString')"
LOCATION="$(resolve_location "$RESOURCE_GROUP" "$LOCATION")"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-$(new_deployment_name key-vault "$ENVIRONMENT_NAME")}"

deployment_json="$(az deployment group create \
  --name "$DEPLOYMENT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --template-file "$SCRIPT_DIR/../bicep/services/key-vault.bicep" \
  --parameters \
    resourcePrefix="$RESOURCE_PREFIX" \
    environmentName="$ENVIRONMENT_NAME" \
    location="$LOCATION" \
    appPrincipalId="$APP_PRINCIPAL_ID" \
    appInsightsConnectionString="$APPINSIGHTS_CONNECTION_STRING" \
    pipelinePrincipalId="$PIPELINE_PRINCIPAL_ID" \
  -o json)"

save_service_outputs "$STATE_FILE" "keyVault" "$RESOURCE_GROUP" "$ENVIRONMENT_NAME" "$RESOURCE_PREFIX" "$deployment_json"

echo "key vault deployment complete"
echo "state file: $STATE_FILE"
print_outputs "$deployment_json"
