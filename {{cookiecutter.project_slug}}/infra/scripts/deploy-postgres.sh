#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=infra/scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'USAGE'
Deploy the database service (template currently provisions Azure SQL server + database).

Usage:
  deploy-postgres.sh --resource-group <name> --sql-admin-password <secret> [options]

Options:
  -g, --resource-group <name>      Existing resource group name (required)
  -e, --environment <name>         Environment name used in naming/tags (default: dev)
  -l, --location <region>          Azure region (default: resource group location)
  -p, --resource-prefix <pref>     Resource prefix (default: {{ cookiecutter.resource_prefix }})
      --sql-admin-login <login>    SQL admin login (default: <resource-prefix>admin)
      --sql-admin-password <pass>  SQL admin password (required; or set SQL_ADMIN_PASSWORD env var)
      --database-name <name>       Database name (default: appdb)
      --entra-admin-object-id <id> Entra admin object id (defaults from state identity.principalId)
      --entra-admin-login <name>   Entra admin display name (default: id-<prefix>-<env>)
  -s, --state-file <path>          Local state file path (default: infra/state/<rg>.json)
      --deployment-name <name>     Override ARM deployment name
  -h, --help                       Show this help text
USAGE
}

RESOURCE_GROUP=""
ENVIRONMENT_NAME="dev"
LOCATION=""
RESOURCE_PREFIX="{{ cookiecutter.resource_prefix }}"
SQL_ADMIN_LOGIN=""
SQL_ADMIN_PASSWORD="${SQL_ADMIN_PASSWORD:-}"
DATABASE_NAME="appdb"
ENTRA_ADMIN_OBJECT_ID=""
ENTRA_ADMIN_LOGIN=""
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
    --sql-admin-login)
      SQL_ADMIN_LOGIN="$2"
      shift 2
      ;;
    --sql-admin-password)
      SQL_ADMIN_PASSWORD="$2"
      shift 2
      ;;
    --database-name)
      DATABASE_NAME="$2"
      shift 2
      ;;
    --entra-admin-object-id)
      ENTRA_ADMIN_OBJECT_ID="$2"
      shift 2
      ;;
    --entra-admin-login)
      ENTRA_ADMIN_LOGIN="$2"
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

if [[ -z "$SQL_ADMIN_PASSWORD" ]]; then
  echo "error: SQL admin password is required via --sql-admin-password or SQL_ADMIN_PASSWORD env var" >&2
  usage
  exit 1
fi

require_command az
require_command jq

if [[ -z "$STATE_FILE" ]]; then
  STATE_FILE="$(default_state_file "$SCRIPT_DIR" "$RESOURCE_GROUP")"
fi
ensure_state_file "$STATE_FILE"

if [[ -z "$SQL_ADMIN_LOGIN" ]]; then
  SQL_ADMIN_LOGIN="${RESOURCE_PREFIX}admin"
fi

if [[ -z "$ENTRA_ADMIN_LOGIN" ]]; then
  ENTRA_ADMIN_LOGIN="id-${RESOURCE_PREFIX}-${ENVIRONMENT_NAME}"
fi

ENTRA_ADMIN_OBJECT_ID="$(resolve_required_value "$ENTRA_ADMIN_OBJECT_ID" "$STATE_FILE" '.services.identity.principalId' '--entra-admin-object-id')"
LOCATION="$(resolve_location "$RESOURCE_GROUP" "$LOCATION")"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-$(new_deployment_name postgres "$ENVIRONMENT_NAME")}"

deployment_json="$(az deployment group create \
  --name "$DEPLOYMENT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --template-file "$SCRIPT_DIR/../bicep/services/postgres.bicep" \
  --parameters \
    resourcePrefix="$RESOURCE_PREFIX" \
    environmentName="$ENVIRONMENT_NAME" \
    location="$LOCATION" \
    sqlAdminLogin="$SQL_ADMIN_LOGIN" \
    sqlAdminPassword="$SQL_ADMIN_PASSWORD" \
    databaseName="$DATABASE_NAME" \
    entraAdminObjectId="$ENTRA_ADMIN_OBJECT_ID" \
    entraAdminLogin="$ENTRA_ADMIN_LOGIN" \
  -o json)"

save_service_outputs "$STATE_FILE" "postgres" "$RESOURCE_GROUP" "$ENVIRONMENT_NAME" "$RESOURCE_PREFIX" "$deployment_json"

echo "database deployment complete"
echo "state file: $STATE_FILE"
print_outputs "$deployment_json"
