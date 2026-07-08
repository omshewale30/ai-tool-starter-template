#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=infra/scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'USAGE'
Deploy the web Container App.

Usage:
  deploy-web-app.sh --resource-group <name> --image <acr/image:tag> [options]

Options:
  -g, --resource-group <name>            Existing resource group name (required)
      --image <acr/image:tag>            Web container image (required; or set WEB_IMAGE env var)
  -e, --environment <name>               Environment name used in naming/tags (default: dev)
  -l, --location <region>                Azure region (default: resource group location)
  -p, --resource-prefix <pref>           Resource prefix (default: {{ cookiecutter.resource_prefix }})
      --tenant-id <guid>                 Entra tenant id (default: {{ cookiecutter.entra_tenant_id }})
      --entra-frontend-client-id <guid>  Frontend SPA client id (default template value)
      --entra-backend-app-id-uri <uri>   Backend app id URI (default template value)
      --auth-disabled <true|false>       Set true only for troubleshooting (default: false)
      --environment-id <id>              Container Apps env id (defaults from state containerAppsEnv.environmentId)
      --default-domain <domain>          Container Apps default domain (defaults from state containerAppsEnv.defaultDomain)
      --identity-id <id>                 User-assigned identity id (defaults from state identity.id)
      --registry-server <server>         ACR login server (defaults from state registry.loginServer)
  -s, --state-file <path>                Local state file path (default: infra/state/<rg>.json)
      --deployment-name <name>           Override ARM deployment name
  -h, --help                             Show this help text
USAGE
}

RESOURCE_GROUP=""
IMAGE="${WEB_IMAGE:-}"
ENVIRONMENT_NAME="dev"
LOCATION=""
RESOURCE_PREFIX="{{ cookiecutter.resource_prefix }}"
TENANT_ID="{{ cookiecutter.entra_tenant_id }}"
ENTRA_FRONTEND_CLIENT_ID="{{ cookiecutter.frontend_client_id }}"
ENTRA_BACKEND_APP_ID_URI="{{ cookiecutter.backend_app_id_uri }}"
AUTH_DISABLED="false"
ENVIRONMENT_ID=""
DEFAULT_DOMAIN=""
IDENTITY_ID=""
REGISTRY_SERVER=""
STATE_FILE=""
DEPLOYMENT_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -g|--resource-group)
      RESOURCE_GROUP="$2"
      shift 2
      ;;
    --image)
      IMAGE="$2"
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
    --tenant-id)
      TENANT_ID="$2"
      shift 2
      ;;
    --entra-frontend-client-id)
      ENTRA_FRONTEND_CLIENT_ID="$2"
      shift 2
      ;;
    --entra-backend-app-id-uri)
      ENTRA_BACKEND_APP_ID_URI="$2"
      shift 2
      ;;
    --auth-disabled)
      AUTH_DISABLED="$2"
      shift 2
      ;;
    --environment-id)
      ENVIRONMENT_ID="$2"
      shift 2
      ;;
    --default-domain)
      DEFAULT_DOMAIN="$2"
      shift 2
      ;;
    --identity-id)
      IDENTITY_ID="$2"
      shift 2
      ;;
    --registry-server)
      REGISTRY_SERVER="$2"
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

if [[ -z "$IMAGE" ]]; then
  echo "error: --image is required (or set WEB_IMAGE)" >&2
  usage
  exit 1
fi

if [[ "$AUTH_DISABLED" != "true" && "$AUTH_DISABLED" != "false" ]]; then
  echo "error: --auth-disabled must be true or false" >&2
  exit 1
fi

require_command az
require_command jq

if [[ -z "$STATE_FILE" ]]; then
  STATE_FILE="$(default_state_file "$SCRIPT_DIR" "$RESOURCE_GROUP")"
fi
ensure_state_file "$STATE_FILE"

ENVIRONMENT_ID="$(resolve_required_value "$ENVIRONMENT_ID" "$STATE_FILE" '.services.containerAppsEnv.environmentId' '--environment-id')"
DEFAULT_DOMAIN="$(resolve_required_value "$DEFAULT_DOMAIN" "$STATE_FILE" '.services.containerAppsEnv.defaultDomain' '--default-domain')"
IDENTITY_ID="$(resolve_required_value "$IDENTITY_ID" "$STATE_FILE" '.services.identity.id' '--identity-id')"
REGISTRY_SERVER="$(resolve_required_value "$REGISTRY_SERVER" "$STATE_FILE" '.services.registry.loginServer' '--registry-server')"

LOCATION="$(resolve_location "$RESOURCE_GROUP" "$LOCATION")"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-$(new_deployment_name web-app "$ENVIRONMENT_NAME")}"

deployment_json="$(az deployment group create \
  --name "$DEPLOYMENT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --template-file "$SCRIPT_DIR/../bicep/services/web-app.bicep" \
  --parameters \
    resourcePrefix="$RESOURCE_PREFIX" \
    environmentName="$ENVIRONMENT_NAME" \
    location="$LOCATION" \
    tenantId="$TENANT_ID" \
    image="$IMAGE" \
    environmentId="$ENVIRONMENT_ID" \
    defaultDomain="$DEFAULT_DOMAIN" \
    userAssignedIdentityId="$IDENTITY_ID" \
    registryServer="$REGISTRY_SERVER" \
    entraFrontendClientId="$ENTRA_FRONTEND_CLIENT_ID" \
    entraBackendAppIdUri="$ENTRA_BACKEND_APP_ID_URI" \
    authDisabled="$AUTH_DISABLED" \
  -o json)"

save_service_outputs "$STATE_FILE" "webApp" "$RESOURCE_GROUP" "$ENVIRONMENT_NAME" "$RESOURCE_PREFIX" "$deployment_json"

echo "web app deployment complete"
echo "state file: $STATE_FILE"
print_outputs "$deployment_json"
