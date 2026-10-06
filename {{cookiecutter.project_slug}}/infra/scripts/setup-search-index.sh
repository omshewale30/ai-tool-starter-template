#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=infra/scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'USAGE'
Create or update the RAG pipeline inside Azure AI Search: the Blob data source,
the index (with an Azure OpenAI vectorizer for queries), the skillset (chunking
and Azure OpenAI embeddings), and the indexer. Safe to re-run.

Usage:
  setup-search-index.sh --resource-group <name> --aoai-endpoint <url> \
    --embedding-deployment <name> [options]

Options:
  -g, --resource-group <name>        Resource group (used to locate the state file)
      --aoai-endpoint <url>          UNC Azure OpenAI endpoint (or AZURE_AI_FOUNDRY_ENDPOINT)
      --embedding-deployment <name>  Embedding deployment name
                                     (or AZURE_AI_FOUNDRY_EMBEDDING_DEPLOYMENT_NAME)
      --embedding-model <name>       Model behind that deployment (default: text-embedding-3-small)
      --dimensions <n>               Vector dimensions for that model (default: 1536)
      --index <name>                 Index name; must match AZURE_SEARCH_INDEX (default: documents)
      --search-name <name>           Search service (default: state search.searchName)
      --storage-account-id <id>      Storage account resource id (default: state search.storageAccountId)
      --container <name>             Documents container (default: state search.documentsContainerName)
      --run                          Run the indexer now instead of waiting for its hourly schedule
  -s, --state-file <path>            Local state file path (default: infra/state/<rg>.json)
  -h, --help                         Show this help text

Prerequisites (docs/rag.md):
  - you hold "Search Service Contributor" on the search service;
  - the search service's identity (deploy-search.sh output searchPrincipalId) holds
    "Cognitive Services OpenAI User" on UNC's Azure OpenAI resource.
USAGE
}

API_VERSION="2026-04-01"
DEFINITIONS="$SCRIPT_DIR/../search"

RESOURCE_GROUP=""
AOAI_ENDPOINT="${AZURE_AI_FOUNDRY_ENDPOINT:-}"
EMBEDDING_DEPLOYMENT="${AZURE_AI_FOUNDRY_EMBEDDING_DEPLOYMENT_NAME:-}"
EMBEDDING_MODEL="text-embedding-3-small"
DIMENSIONS="1536"
INDEX="documents"
SEARCH_NAME=""
STORAGE_ACCOUNT_ID=""
CONTAINER=""
RUN_NOW="false"
STATE_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -g|--resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    --aoai-endpoint) AOAI_ENDPOINT="$2"; shift 2 ;;
    --embedding-deployment) EMBEDDING_DEPLOYMENT="$2"; shift 2 ;;
    --embedding-model) EMBEDDING_MODEL="$2"; shift 2 ;;
    --dimensions) DIMENSIONS="$2"; shift 2 ;;
    --index) INDEX="$2"; shift 2 ;;
    --search-name) SEARCH_NAME="$2"; shift 2 ;;
    --storage-account-id) STORAGE_ACCOUNT_ID="$2"; shift 2 ;;
    --container) CONTAINER="$2"; shift 2 ;;
    --run) RUN_NOW="true"; shift ;;
    -s|--state-file) STATE_FILE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$RESOURCE_GROUP" || -z "$AOAI_ENDPOINT" || -z "$EMBEDDING_DEPLOYMENT" ]]; then
  echo "error: --resource-group, --aoai-endpoint and --embedding-deployment are required" >&2
  usage
  exit 1
fi
if [[ ! "$DIMENSIONS" =~ ^[0-9]+$ ]]; then
  echo "error: --dimensions must be a number" >&2
  exit 1
fi

require_command az
require_command jq

if [[ -z "$STATE_FILE" ]]; then
  STATE_FILE="$(default_state_file "$SCRIPT_DIR" "$RESOURCE_GROUP")"
fi
ensure_state_file "$STATE_FILE"

SEARCH_NAME="$(resolve_required_value "$SEARCH_NAME" "$STATE_FILE" '.services.search.searchName' '--search-name')"
STORAGE_ACCOUNT_ID="$(resolve_required_value "$STORAGE_ACCOUNT_ID" "$STATE_FILE" '.services.search.storageAccountId' '--storage-account-id')"
CONTAINER="$(resolve_required_value "$CONTAINER" "$STATE_FILE" '.services.search.documentsContainerName' '--container')"
ENDPOINT="https://${SEARCH_NAME}.search.windows.net"
AOAI_ENDPOINT="${AOAI_ENDPOINT%/}"

# Render one definition: substitute placeholders, then check the result is JSON.
render() {
  local file="$1" out
  out="$(sed \
    -e "s|__INDEX__|${INDEX}|g" \
    -e "s|__CONTAINER__|${CONTAINER}|g" \
    -e "s|__STORAGE_ACCOUNT_ID__|${STORAGE_ACCOUNT_ID}|g" \
    -e "s|__AOAI_ENDPOINT__|${AOAI_ENDPOINT}|g" \
    -e "s|__EMBEDDING_DEPLOYMENT__|${EMBEDDING_DEPLOYMENT}|g" \
    -e "s|__EMBEDDING_MODEL__|${EMBEDDING_MODEL}|g" \
    -e "s|__DIMENSIONS__|${DIMENSIONS}|g" \
    "$DEFINITIONS/$file")"
  jq -e . >/dev/null <<<"$out"
  printf '%s' "$out"
}

# PUT <collection> <name> <definition file>, authenticated with your Entra token.
put() {
  local collection="$1" name="$2" file="$3" body
  body="$(mktemp)"
  render "$file" >"$body"
  echo "PUT $collection/$name"
  az rest --method put \
    --url "${ENDPOINT}/${collection}/${name}?api-version=${API_VERSION}" \
    --resource "https://search.azure.com" \
    --headers "Content-Type=application/json" \
    --body "@$body" \
    --output none
  rm -f "$body"
}

put datasources "${INDEX}-blob" datasource.json
put indexes "$INDEX" index.json
put skillsets "${INDEX}-skillset" skillset.json
put indexers "${INDEX}-indexer" indexer.json

if [[ "$RUN_NOW" == "true" ]]; then
  az rest --method post \
    --url "${ENDPOINT}/indexers/${INDEX}-indexer/run?api-version=${API_VERSION}" \
    --resource "https://search.azure.com" --output none
  echo "indexer started; check status with:"
  echo "  az rest --method get --url '${ENDPOINT}/indexers/${INDEX}-indexer/status?api-version=${API_VERSION}' --resource https://search.azure.com"
fi

echo "search pipeline ready: index '$INDEX' on $ENDPOINT"
echo "Set the GitHub variables AZURE_SEARCH_ENDPOINT=$ENDPOINT and AZURE_SEARCH_INDEX=$INDEX."
