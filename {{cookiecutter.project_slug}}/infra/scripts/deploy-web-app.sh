#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=infra/scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'USAGE'
Create the web Container App (public ingress) with a bootstrap image. It forwards
/api/* to the API app's internal FQDN, so create the API app first.

Usage:
  deploy-web-app.sh --resource-group <name> [options]

After this, scripts/cd.sh (the CD workflow) owns the image and env.

Options:
  -g, --resource-group <name>        Existing resource group name (required)
  -e, --environment <name>           Environment name used in naming/tags (default: dev)
  -l, --location <region>            Azure region (default: resource group location)
  -p, --resource-prefix <pref>       Resource prefix (default: {{ cookiecutter.resource_prefix }})
      --image <ref>                  Bootstrap image (default: Container Apps quickstart)
      --tenant-id <guid>             Entra tenant id (default: {{ cookiecutter.entra_tenant_id }})
      --entra-client-id <guid>       Web (SPA) app registration client id (default: template value)
      --entra-api-scope <scope>      API scope (default: {{ cookiecutter.backend_app_id_uri }}/access_as_user)
      --environment-id <id>          Container Apps env id (default: state containerAppsEnv.environmentId)
      --identity-id <id>             User-assigned identity id (default: state identity.id)
      --registry-server <server>     ACR login server (default: state registry.loginServer)
      --recreate                     Re-run even though the app exists (resets image and env)
  -s, --state-file <path>            Local state file path (default: infra/state/<rg>.json)
      --deployment-name <name>       Override ARM deployment name
  -h, --help                         Show this help text
USAGE
}

RESOURCE_GROUP=""
ENVIRONMENT_NAME="dev"
LOCATION=""
RESOURCE_PREFIX="{{ cookiecutter.resource_prefix }}"
IMAGE=""
TENANT_ID="{{ cookiecutter.entra_tenant_id }}"
ENTRA_CLIENT_ID="{{ cookiecutter.frontend_client_id }}"
ENTRA_API_SCOPE="{{ cookiecutter.backend_app_id_uri }}/access_as_user"
ENVIRONMENT_ID=""
IDENTITY_ID=""
REGISTRY_SERVER=""
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
    --tenant-id) TENANT_ID="$2"; shift 2 ;;
    --entra-client-id) ENTRA_CLIENT_ID="$2"; shift 2 ;;
    --entra-api-scope) ENTRA_API_SCOPE="$2"; shift 2 ;;
    --environment-id) ENVIRONMENT_ID="$2"; shift 2 ;;
    --identity-id) IDENTITY_ID="$2"; shift 2 ;;
    --registry-server) REGISTRY_SERVER="$2"; shift 2 ;;
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

APP_NAME="ca-${RESOURCE_PREFIX}-${ENVIRONMENT_NAME}-web"
refuse_if_app_exists "$APP_NAME" "$RESOURCE_GROUP" "$RECREATE"

ENVIRONMENT_ID="$(resolve_required_value "$ENVIRONMENT_ID" "$STATE_FILE" '.services.containerAppsEnv.environmentId' '--environment-id')"
IDENTITY_ID="$(resolve_required_value "$IDENTITY_ID" "$STATE_FILE" '.services.identity.id' '--identity-id')"
REGISTRY_SERVER="$(resolve_required_value "$REGISTRY_SERVER" "$STATE_FILE" '.services.registry.loginServer' '--registry-server')"
LOCATION="$(resolve_location "$RESOURCE_GROUP" "$LOCATION")"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-$(new_deployment_name web-app "$ENVIRONMENT_NAME")}"

image_args=()
[[ -n "$IMAGE" ]] && image_args=(image="$IMAGE")

deployment_json="$(az deployment group create \
  --name "$DEPLOYMENT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --template-file "$SCRIPT_DIR/../bicep/services/web-app.bicep" \
  --parameters \
    resourcePrefix="$RESOURCE_PREFIX" \
    environmentName="$ENVIRONMENT_NAME" \
    location="$LOCATION" \
    environmentId="$ENVIRONMENT_ID" \
    userAssignedIdentityId="$IDENTITY_ID" \
    registryServer="$REGISTRY_SERVER" \
    tenantId="$TENANT_ID" \
    entraClientId="$ENTRA_CLIENT_ID" \
    entraApiScope="$ENTRA_API_SCOPE" \
    ${image_args[@]+"${image_args[@]}"} \
  -o json)"

save_service_outputs "$STATE_FILE" "webApp" "$RESOURCE_GROUP" "$ENVIRONMENT_NAME" "$RESOURCE_PREFIX" "$deployment_json"

echo "web app created"
echo "state file: $STATE_FILE"
print_outputs "$deployment_json"
echo
echo "Register <webUrl>/auth as a SPA redirect URI on the web app registration."
