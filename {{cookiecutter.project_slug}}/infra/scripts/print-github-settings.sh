#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=infra/scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'USAGE'
Print the `gh` commands that configure GitHub for CI/CD, filled in from the Terraform
outputs of envs/shared and envs/<environment>. Prints only; review, fill the
<placeholders>, then run them.

Usage:
  print-github-settings.sh --pipeline-client-id <guid> [--environment <name>]

Options:
      --pipeline-client-id <guid>  Client id of the CI/CD app registration (OIDC)
  -e, --environment <name>         Terraform env root and GitHub environment (default: dev)
  -h, --help                       Show this help text
USAGE
}

PIPELINE_CLIENT_ID=""
GH_ENVIRONMENT="dev"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pipeline-client-id) PIPELINE_CLIENT_ID="$2"; shift 2 ;;
    -e|--environment) GH_ENVIRONMENT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$PIPELINE_CLIENT_ID" ]]; then
  usage
  exit 1
fi
require_command az
require_command jq
require_command terraform

SHARED="$(terraform_outputs envs/shared)"
ENV="$(terraform_outputs "envs/$GH_ENVIRONMENT")"
out() { output_value "$ENV" "$1"; }

TENANT_ID="$(az account show --query tenantId -o tsv)"
SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
KEY_VAULT_NAME="$(out .key_vault_name)"

cat <<COMMANDS
# ---- Repository variables (read by CI's publish job, which has no environment) ----
gh variable set AZURE_CLIENT_ID --body "$PIPELINE_CLIENT_ID"
gh variable set AZURE_TENANT_ID --body "$TENANT_ID"
gh variable set AZURE_SUBSCRIPTION_ID --body "$SUBSCRIPTION_ID"
gh variable set ACR_NAME --body "$(output_value "$SHARED" .registry_name)"

# ---- '$GH_ENVIRONMENT' environment: deploy targets (scripts/cd.sh) ----
gh variable set RESOURCE_GROUP --env $GH_ENVIRONMENT --body "$(out .resource_group_name)"
gh variable set KEY_VAULT_NAME --env $GH_ENVIRONMENT --body "$KEY_VAULT_NAME"
gh variable set API_APP_NAME --env $GH_ENVIRONMENT --body "$(out .api_app_name)"
gh variable set WEB_APP_NAME --env $GH_ENVIRONMENT --body "$(out .web_app_name)"
gh variable set AZURE_WEB_URL --env $GH_ENVIRONMENT --body "$(out .web_url)"

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
gh variable set AZURE_STORAGE_ACCOUNT_URL --env $GH_ENVIRONMENT --body "$(out .storage_blob_endpoint)"

# ---- '$GH_ENVIRONMENT' environment secret (cd.sh writes it to Key Vault as database-url) ----
# Terraform seeded database-url from the generated admin password; copy it to GitHub
# without printing it:
az keyvault secret show --vault-name $KEY_VAULT_NAME --name database-url --query value -o tsv \\
  | gh secret set DATABASE_URL --env $GH_ENVIRONMENT
COMMANDS
