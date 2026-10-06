#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=infra/scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'USAGE'
Deploy optional Azure AI Search service.

Usage:
  deploy-search.sh --resource-group <name> [options]

Options:
  -g, --resource-group <name>    Existing resource group name (required)
  -e, --environment <name>       Environment name used in naming/tags (default: dev)
  -l, --location <region>        Azure region (default: resource group location)
  -p, --resource-prefix <pref>   Resource prefix (default: {{ cookiecutter.resource_prefix }})
      --app-principal-id <id>    Managed identity principal id (defaults from state identity.principalId)
      --storage-account <name>   Storage account holding documents (defaults from state storage.storageAccountName)
  -s, --state-file <path>        Local state file path (default: infra/state/<rg>.json)
      --deployment-name <name>   Override ARM deployment name
  -h, --help                     Show this help text
USAGE
}

RESOURCE_GROUP=""
ENVIRONMENT_NAME="dev"
LOCATION=""
RESOURCE_PREFIX="{{ cookiecutter.resource_prefix }}"
APP_PRINCIPAL_ID=""
STORAGE_ACCOUNT=""
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
    --storage-account)
      STORAGE_ACCOUNT="$2"
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
STORAGE_ACCOUNT="$(resolve_required_value "$STORAGE_ACCOUNT" "$STATE_FILE" '.services.storage.storageAccountName' '--storage-account')"
LOCATION="$(resolve_location "$RESOURCE_GROUP" "$LOCATION")"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-$(new_deployment_name search "$ENVIRONMENT_NAME")}"

deployment_json="$(az deployment group create \
  --name "$DEPLOYMENT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --template-file "$SCRIPT_DIR/../bicep/services/search.bicep" \
  --parameters \
    resourcePrefix="$RESOURCE_PREFIX" \
    environmentName="$ENVIRONMENT_NAME" \
    location="$LOCATION" \
    appPrincipalId="$APP_PRINCIPAL_ID" \
    storageAccountName="$STORAGE_ACCOUNT" \
  -o json)"

save_service_outputs "$STATE_FILE" "search" "$RESOURCE_GROUP" "$ENVIRONMENT_NAME" "$RESOURCE_PREFIX" "$deployment_json"

echo "search deployment complete"
echo "state file: $STATE_FILE"
echo "Next: hand the searchPrincipalId to UNC for Azure OpenAI access, then run"
echo "      setup-search-index.sh (docs/rag.md)."
print_outputs "$deployment_json"
