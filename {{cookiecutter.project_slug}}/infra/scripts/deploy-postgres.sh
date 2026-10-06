#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=infra/scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'USAGE'
Deploy Azure Database for PostgreSQL Flexible Server and the app database.

Usage:
  PG_ADMIN_PASSWORD=<secret> deploy-postgres.sh --resource-group <name> [options]

Options:
  -g, --resource-group <name>    Existing resource group name (required)
  -e, --environment <name>       Environment name used in naming/tags (default: dev)
  -l, --location <region>        Azure region (default: resource group location)
  -p, --resource-prefix <pref>   Resource prefix (default: {{ cookiecutter.resource_prefix }})
      --admin-login <login>      Admin login (default: <resource-prefix>admin)
      --database-name <name>     Database name (default: appdb)
  -s, --state-file <path>        Local state file path (default: infra/state/<rg>.json)
      --deployment-name <name>   Override ARM deployment name
  -h, --help                     Show this help text

The admin password is read from PG_ADMIN_PASSWORD (letters and digits only, so
it can be embedded in DATABASE_URL). It is never written to the state file.

Afterwards, set the GitHub `dev` environment secret DATABASE_URL to:
  postgresql+psycopg://<admin-login>:<password>@<serverFqdn>:5432/<database>?sslmode=require
USAGE
}

RESOURCE_GROUP=""
ENVIRONMENT_NAME="dev"
LOCATION=""
RESOURCE_PREFIX="{{ cookiecutter.resource_prefix }}"
ADMIN_LOGIN=""
DATABASE_NAME="appdb"
STATE_FILE=""
DEPLOYMENT_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -g|--resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    -e|--environment) ENVIRONMENT_NAME="$2"; shift 2 ;;
    -l|--location) LOCATION="$2"; shift 2 ;;
    -p|--resource-prefix) RESOURCE_PREFIX="$2"; shift 2 ;;
    --admin-login) ADMIN_LOGIN="$2"; shift 2 ;;
    --database-name) DATABASE_NAME="$2"; shift 2 ;;
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

PG_ADMIN_PASSWORD="${PG_ADMIN_PASSWORD:-}"
if [[ -z "$PG_ADMIN_PASSWORD" ]]; then
  echo "error: set PG_ADMIN_PASSWORD (letters and digits only)" >&2
  exit 1
fi
if [[ ! "$PG_ADMIN_PASSWORD" =~ ^[A-Za-z0-9]{16,}$ ]]; then
  echo "error: PG_ADMIN_PASSWORD must be at least 16 letters/digits (it is embedded in DATABASE_URL)" >&2
  exit 1
fi

require_command az
require_command jq

if [[ -z "$STATE_FILE" ]]; then
  STATE_FILE="$(default_state_file "$SCRIPT_DIR" "$RESOURCE_GROUP")"
fi
ensure_state_file "$STATE_FILE"

ADMIN_LOGIN="${ADMIN_LOGIN:-${RESOURCE_PREFIX}admin}"
LOCATION="$(resolve_location "$RESOURCE_GROUP" "$LOCATION")"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-$(new_deployment_name postgres "$ENVIRONMENT_NAME")}"

# The password goes through a temporary parameters file, not argv, so it never
# shows up in the process list.
params_file="$(mktemp)"
trap 'rm -f "$params_file"' EXIT
jq -n --arg password "$PG_ADMIN_PASSWORD" \
  '{"$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
    contentVersion: "1.0.0.0",
    parameters: {adminPassword: {value: $password}}}' >"$params_file"

deployment_json="$(az deployment group create \
  --name "$DEPLOYMENT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --template-file "$SCRIPT_DIR/../bicep/services/postgres.bicep" \
  --parameters "@$params_file" \
  --parameters \
    resourcePrefix="$RESOURCE_PREFIX" \
    environmentName="$ENVIRONMENT_NAME" \
    location="$LOCATION" \
    adminLogin="$ADMIN_LOGIN" \
    databaseName="$DATABASE_NAME" \
  -o json)"

save_service_outputs "$STATE_FILE" "postgres" "$RESOURCE_GROUP" "$ENVIRONMENT_NAME" "$RESOURCE_PREFIX" "$deployment_json"

echo "postgres deployment complete"
echo "state file: $STATE_FILE"
print_outputs "$deployment_json"
echo
echo "Next: set the GitHub 'dev' environment secret DATABASE_URL (see docs/runbook.md)."
