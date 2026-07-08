#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=infra/scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'USAGE'
Deploy the API Container App.

Usage:
  deploy-api-app.sh --resource-group <name> --image <acr/image:tag> [options]

Options:
  -g, --resource-group <name>            Existing resource group name (required)
      --image <acr/image:tag>            API container image (required; or set API_IMAGE env var)
  -e, --environment <name>               Environment name used in naming/tags (default: dev)
  -l, --location <region>                Azure region (default: resource group location)
  -p, --resource-prefix <pref>           Resource prefix (default: {{ cookiecutter.resource_prefix }})
      --tenant-id <guid>                 Entra tenant id (default: {{ cookiecutter.entra_tenant_id }})
      --entra-backend-client-id <guid>   Backend app registration client id (default template value)
      --entra-backend-app-id-uri <uri>   Backend app id URI (default template value)
      --admin-group-id <guid>            Optional admin group object id
      --ai-provider <mock|foundry>       AI provider (default: foundry)
      --auth-mode <entra|disabled>       Auth mode (default: entra)
      --foundry-endpoint <url>           Optional Foundry endpoint (or AZURE_AI_FOUNDRY_ENDPOINT env var)
      --foundry-deployment-name <name>   Foundry model deployment name (default: gpt-4o-mini)
      --foundry-api-version <version>    Foundry API version (default: 2024-08-01-preview)
      --search-endpoint <url>            Optional Search endpoint (defaults from state search.searchEndpoint)
      --environment-id <id>              Container Apps env id (defaults from state containerAppsEnv.environmentId)
      --default-domain <domain>          Container Apps default domain (defaults from state containerAppsEnv.defaultDomain)
      --identity-id <id>                 User-assigned identity id (defaults from state identity.id)
      --identity-client-id <id>          User-assigned identity client id (defaults from state identity.clientId)
      --registry-server <server>         ACR login server (defaults from state registry.loginServer)
      --database-server-fqdn <host>      Database server FQDN (defaults from state postgres.serverFqdn)
      --database-name <name>             Database name (defaults from state postgres.databaseName or appdb)
      --storage-blob-endpoint <url>      Blob endpoint (defaults from state storage.blobEndpoint)
      --storage-container-name <name>    Blob container name (defaults from state storage.containerName)
      --key-vault-uri <uri>              Key Vault URI (defaults from state keyVault.keyVaultUri)
  -s, --state-file <path>                Local state file path (default: infra/state/<rg>.json)
      --deployment-name <name>           Override ARM deployment name
  -h, --help                             Show this help text
USAGE
}

RESOURCE_GROUP=""
IMAGE="${API_IMAGE:-}"
ENVIRONMENT_NAME="dev"
LOCATION=""
RESOURCE_PREFIX="{{ cookiecutter.resource_prefix }}"
TENANT_ID="{{ cookiecutter.entra_tenant_id }}"
ENTRA_BACKEND_CLIENT_ID="{{ cookiecutter.backend_client_id }}"
ENTRA_BACKEND_APP_ID_URI="{{ cookiecutter.backend_app_id_uri }}"
ADMIN_GROUP_ID=""
AI_PROVIDER="foundry"
AUTH_MODE="entra"
FOUNDRY_ENDPOINT="${AZURE_AI_FOUNDRY_ENDPOINT:-}"
FOUNDRY_DEPLOYMENT_NAME="gpt-4o-mini"
FOUNDRY_API_VERSION="2024-08-01-preview"
SEARCH_ENDPOINT=""
ENVIRONMENT_ID=""
DEFAULT_DOMAIN=""
IDENTITY_ID=""
IDENTITY_CLIENT_ID=""
REGISTRY_SERVER=""
DATABASE_SERVER_FQDN=""
DATABASE_NAME=""
STORAGE_BLOB_ENDPOINT=""
STORAGE_CONTAINER_NAME=""
KEY_VAULT_URI=""
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
    --entra-backend-client-id)
      ENTRA_BACKEND_CLIENT_ID="$2"
      shift 2
      ;;
    --entra-backend-app-id-uri)
      ENTRA_BACKEND_APP_ID_URI="$2"
      shift 2
      ;;
    --admin-group-id)
      ADMIN_GROUP_ID="$2"
      shift 2
      ;;
    --ai-provider)
      AI_PROVIDER="$2"
      shift 2
      ;;
    --auth-mode)
      AUTH_MODE="$2"
      shift 2
      ;;
    --foundry-endpoint)
      FOUNDRY_ENDPOINT="$2"
      shift 2
      ;;
    --foundry-deployment-name)
      FOUNDRY_DEPLOYMENT_NAME="$2"
      shift 2
      ;;
    --foundry-api-version)
      FOUNDRY_API_VERSION="$2"
      shift 2
      ;;
    --search-endpoint)
      SEARCH_ENDPOINT="$2"
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
    --identity-client-id)
      IDENTITY_CLIENT_ID="$2"
      shift 2
      ;;
    --registry-server)
      REGISTRY_SERVER="$2"
      shift 2
      ;;
    --database-server-fqdn)
      DATABASE_SERVER_FQDN="$2"
      shift 2
      ;;
    --database-name)
      DATABASE_NAME="$2"
      shift 2
      ;;
    --storage-blob-endpoint)
      STORAGE_BLOB_ENDPOINT="$2"
      shift 2
      ;;
    --storage-container-name)
      STORAGE_CONTAINER_NAME="$2"
      shift 2
      ;;
    --key-vault-uri)
      KEY_VAULT_URI="$2"
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
  echo "error: --image is required (or set API_IMAGE)" >&2
  usage
  exit 1
fi

if [[ "$AI_PROVIDER" != "mock" && "$AI_PROVIDER" != "foundry" ]]; then
  echo "error: --ai-provider must be 'mock' or 'foundry'" >&2
  exit 1
fi

if [[ "$AUTH_MODE" != "entra" && "$AUTH_MODE" != "disabled" ]]; then
  echo "error: --auth-mode must be 'entra' or 'disabled'" >&2
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
IDENTITY_CLIENT_ID="$(resolve_required_value "$IDENTITY_CLIENT_ID" "$STATE_FILE" '.services.identity.clientId' '--identity-client-id')"
REGISTRY_SERVER="$(resolve_required_value "$REGISTRY_SERVER" "$STATE_FILE" '.services.registry.loginServer' '--registry-server')"
DATABASE_SERVER_FQDN="$(resolve_required_value "$DATABASE_SERVER_FQDN" "$STATE_FILE" '.services.postgres.serverFqdn' '--database-server-fqdn')"
STORAGE_BLOB_ENDPOINT="$(resolve_required_value "$STORAGE_BLOB_ENDPOINT" "$STATE_FILE" '.services.storage.blobEndpoint' '--storage-blob-endpoint')"
STORAGE_CONTAINER_NAME="$(resolve_required_value "$STORAGE_CONTAINER_NAME" "$STATE_FILE" '.services.storage.containerName' '--storage-container-name')"
KEY_VAULT_URI="$(resolve_required_value "$KEY_VAULT_URI" "$STATE_FILE" '.services.keyVault.keyVaultUri' '--key-vault-uri')"
SEARCH_ENDPOINT="$(resolve_optional_value "$SEARCH_ENDPOINT" "$STATE_FILE" '.services.search.searchEndpoint')"

if [[ -z "$DATABASE_NAME" ]]; then
  DATABASE_NAME="$(resolve_optional_value "$DATABASE_NAME" "$STATE_FILE" '.services.postgres.databaseName')"
fi
if [[ -z "$DATABASE_NAME" || "$DATABASE_NAME" == "null" ]]; then
  DATABASE_NAME="appdb"
fi

LOCATION="$(resolve_location "$RESOURCE_GROUP" "$LOCATION")"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-$(new_deployment_name api-app "$ENVIRONMENT_NAME")}"

deployment_json="$(az deployment group create \
  --name "$DEPLOYMENT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --template-file "$SCRIPT_DIR/../bicep/services/api-app.bicep" \
  --parameters \
    resourcePrefix="$RESOURCE_PREFIX" \
    environmentName="$ENVIRONMENT_NAME" \
    location="$LOCATION" \
    tenantId="$TENANT_ID" \
    image="$IMAGE" \
    environmentId="$ENVIRONMENT_ID" \
    defaultDomain="$DEFAULT_DOMAIN" \
    userAssignedIdentityId="$IDENTITY_ID" \
    userAssignedIdentityClientId="$IDENTITY_CLIENT_ID" \
    registryServer="$REGISTRY_SERVER" \
    databaseServerFqdn="$DATABASE_SERVER_FQDN" \
    databaseName="$DATABASE_NAME" \
    storageBlobEndpoint="$STORAGE_BLOB_ENDPOINT" \
    storageContainerName="$STORAGE_CONTAINER_NAME" \
    keyVaultUri="$KEY_VAULT_URI" \
    entraBackendClientId="$ENTRA_BACKEND_CLIENT_ID" \
    entraBackendAppIdUri="$ENTRA_BACKEND_APP_ID_URI" \
    adminGroupId="$ADMIN_GROUP_ID" \
    aiProvider="$AI_PROVIDER" \
    authMode="$AUTH_MODE" \
    foundryEndpoint="$FOUNDRY_ENDPOINT" \
    foundryDeploymentName="$FOUNDRY_DEPLOYMENT_NAME" \
    foundryApiVersion="$FOUNDRY_API_VERSION" \
    searchEndpoint="$SEARCH_ENDPOINT" \
  -o json)"

save_service_outputs "$STATE_FILE" "apiApp" "$RESOURCE_GROUP" "$ENVIRONMENT_NAME" "$RESOURCE_PREFIX" "$deployment_json"

echo "api app deployment complete"
echo "state file: $STATE_FILE"
print_outputs "$deployment_json"
