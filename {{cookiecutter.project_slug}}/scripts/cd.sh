#!/usr/bin/env bash
# Promote the images scripts/publish.sh pushed and smoke-tested for $IMAGE_TAG, by digest,
# then verify, and roll back on any failure. Never builds.
#
# Runs inside the shared FO-AI reusable-azure-cd.yml wrapper, which has already checked
# out the commit, rejected a stale main, entered the `dev` environment, and signed in.
#
# Part of the FO-AI repository script contract (scripts/ci.sh, scripts/publish.sh,
# scripts/cd.sh); see the FO-AI/automation README.
#
# From the wrapper: DEPLOY_SHA, IMAGE_TAG, GH_TOKEN, DEPLOYMENT_VARS_JSON,
#                   DEPLOYMENT_SECRETS_JSON (every GitHub variable and secret the run
#                   can see; deploy/env-contract.json says which ones reach an app).
# Settings (GitHub variables, or the environment): RESOURCE_GROUP, ACR_NAME,
#                   KEY_VAULT_NAME, API_APP_NAME, WEB_APP_NAME, AZURE_WEB_URL, and
#                   optionally WEB_URL (a custom domain; defaults to AZURE_WEB_URL) and
#                   IMAGE_PREFIX (defaults to the repository name).
# Optional:         ALLOW_PRUNE=true accepts removing container env vars the contract
#                   does not render. Manual runs only.
#
# Topology: only the web app has public ingress. It forwards /api/* to the API's
# internal address (BACKEND_ORIGIN), so the end-to-end check goes through the web.
#
# Phases. Nothing in 1-3 changes Azure; everything after 4 is rolled back on failure.
#   1. validate inputs (no Azure at all)
#   2. read: target resources, published digests, current app definitions
#   3. render both apps' env from the GitHub variables and secrets, against the
#      contract and their current definitions (catches pruning)
#   4. recheck main, then sync Key Vault, roll out the API (gated on revision health),
#      roll out the web (likewise), and check the site end to end through the web
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Every secret the run inherits, organization secrets included. Kept in an unexported
# variable and handed to the renderer alone: no other command (`az extension add`
# downloads and runs code) may inherit it.
secrets_json="${DEPLOYMENT_SECRETS_JSON:-}"
unset DEPLOYMENT_SECRETS_JSON API_ENV_FILE WEB_ENV_FILE

for name in RUNNER_TEMP GITHUB_STEP_SUMMARY IMAGE_TAG DEPLOY_SHA GITHUB_REPOSITORY GH_TOKEN; do
  if [[ -z "${!name:-}" ]]; then
    printf '::error::%s is required\n' "$name"
    exit 1
  fi
done
if [[ ! "$IMAGE_TAG" =~ ^[0-9a-f]{40}$ ]]; then
  echo '::error::IMAGE_TAG must be a full commit SHA; publish.sh tags images by it'
  exit 1
fi

# The wrapper resolves vars after entering dev, so environment variables can override
# repository variables. An explicit nonempty command environment value wins over both.
deployment_vars="${DEPLOYMENT_VARS_JSON:-}"
[[ -n "$deployment_vars" ]] || deployment_vars='{}'
for name in RESOURCE_GROUP ACR_NAME KEY_VAULT_NAME API_APP_NAME WEB_APP_NAME AZURE_WEB_URL WEB_URL IMAGE_PREFIX; do
  if [[ -z "${!name:-}" ]]; then
    printf -v "$name" '%s' "$(jq -r --arg key "$name" '.[$key] // ""' <<< "$deployment_vars")"
  fi
done
for name in RESOURCE_GROUP ACR_NAME KEY_VAULT_NAME API_APP_NAME WEB_APP_NAME AZURE_WEB_URL; do
  if [[ -z "${!name}" ]]; then
    printf '::error::Set repository or dev environment variable %s before enabling deployment.\n' "$name"
    exit 1
  fi
done
IMAGE_PREFIX="${IMAGE_PREFIX:-${GITHUB_REPOSITORY##*/}}"
# ACR repository names must be lowercase (publish.sh lowercases the same way).
IMAGE_PREFIX="$(tr '[:upper:]' '[:lower:]' <<< "$IMAGE_PREFIX")"
WEB_URL="${WEB_URL:-$AZURE_WEB_URL}"
WEB_URL="${WEB_URL%/}"
AZURE_WEB_URL="${AZURE_WEB_URL%/}"
if [[ -z "$secrets_json" ]]; then
  echo '::error::DEPLOYMENT_SECRETS_JSON is not set; pin FO-AI/automation reusable-azure-cd.yml at a commit that passes it'
  exit 1
fi
export DEPLOYMENT_VARS_JSON="$deployment_vars"

prune_flag=()
[[ "${ALLOW_PRUNE:-}" == true ]] && prune_flag=(--allow-prune)

# A private directory for this run's rendered files. The variables and secrets objects
# are never written anywhere: scripts/deploy_env.py reads them from its environment.
umask 077
deploy_tmp="$(mktemp -d "$RUNNER_TEMP/deploy.XXXXXX")"

API_IMAGE=""
WEB_IMAGE=""
key_vault_synced=0
api_deployed=0
web_deployed=0
outcome="failed before any change to Azure"

rollback() {
  local failed=0
  # Reverse of deploy order. Always attempt the API even if the web restore fails.
  if (( web_deployed )); then
    bash scripts/aca_rollout.sh "$WEB_APP_NAME" "$RESOURCE_GROUP" "$WEB_CONTAINER" \
      "$WEB_PREVIOUS_IMAGE" "$deploy_tmp/web.previous" || {
      echo '::error::Web rollback failed; manual recovery is required'
      failed=1
    }
  fi
  if (( api_deployed )); then
    bash scripts/aca_rollout.sh "$API_APP_NAME" "$RESOURCE_GROUP" "$API_CONTAINER" \
      "$API_PREVIOUS_IMAGE" "$deploy_tmp/api.previous" || {
      echo '::error::API rollback failed; manual recovery is required'
      failed=1
    }
  fi
  if (( key_vault_synced )); then
    # Key Vault keeps every version, so this is recoverable, but not automatically:
    # the restored revisions resolve the newest version on their next restart.
    echo '::warning::Key Vault secrets keep their new versions; restore a previous version by hand if the new values were the problem'
  fi
  return "$failed"
}

finish() {
  local status=$?
  trap - EXIT
  set +e
  if (( status != 0 && (api_deployed || web_deployed) )); then
    if rollback; then
      outcome="failed; rolled back to the previous images and env"
    else
      outcome="failed; rollback FAILED, manual recovery is required"
    fi
  elif (( status != 0 && key_vault_synced )); then
    outcome="failed after the Key Vault sync; no app was changed"
  elif (( status == 0 )); then
    outcome="deployed"
  fi
  rm -rf -- "$deploy_tmp" || status=1
  {
    echo "### dev deploy: ${outcome}"
    echo "- Commit: \`$DEPLOY_SHA\`"
    echo "- API image: \`${API_IMAGE:-not resolved}\`"
    echo "- Web image: \`${WEB_IMAGE:-not resolved}\`"
    echo "- Site: $WEB_URL"
  } >> "$GITHUB_STEP_SUMMARY"
  exit "$status"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

echo "::group::Read targets and published digests"
# A local CLI change, not an Azure one: --replace-env-vars and --remove-all-env-vars
# need a recent containerapp extension, and the runner's may predate them.
az extension add --name containerapp --upgrade --yes --only-show-errors
az group show --name "$RESOURCE_GROUP" --output none
az keyvault show --name "$KEY_VAULT_NAME" --resource-group "$RESOURCE_GROUP" --output none
# The tag only says which build to look up; each revision is created from the digest,
# so a later re-push of the same tag cannot change what is running. Always read from
# ACR: nothing in the environment may substitute a digest.
for service in api web; do
  if ! digest="$(az acr repository show --name "$ACR_NAME" \
      --image "${IMAGE_PREFIX}-${service}:${IMAGE_TAG}" --query digest -o tsv)"; then
    printf '::error::No image %s-%s:%s in %s; publish must succeed before deploy\n' \
      "$IMAGE_PREFIX" "$service" "$IMAGE_TAG" "$ACR_NAME"
    exit 1
  fi
  if [[ ! "$digest" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    printf '::error::%s-%s:%s did not resolve to a sha256 digest (got %q)\n' \
      "$IMAGE_PREFIX" "$service" "$IMAGE_TAG" "$digest"
    exit 1
  fi
  printf -v "$(tr '[:lower:]' '[:upper:]' <<< "$service")_IMAGE" '%s' \
    "$ACR_NAME.azurecr.io/${IMAGE_PREFIX}-${service}@${digest}"
done
echo "api: $API_IMAGE"
echo "web: $WEB_IMAGE"
echo "::endgroup::"

echo "::group::Read the running apps"
# What is running now is what a rollback restores, and what the revision health gate
# needs: a single active revision that cannot scale to zero.
for service in api web; do
  if [[ "$service" == api ]]; then app="$API_APP_NAME"; else app="$WEB_APP_NAME"; fi
  app_json="$deploy_tmp/${service}.app.json"
  az containerapp show --name "$app" --resource-group "$RESOURCE_GROUP" -o json > "$app_json"
  if [[ "$(jq -r '.properties.configuration.activeRevisionsMode' "$app_json")" != Single ]]; then
    printf '::error::%s must use Single revision mode; the health gate checks the one revision serving traffic\n' "$app"
    exit 1
  fi
  if (( $(jq -r '.properties.template.scale.minReplicas // 0' "$app_json") < 1 )); then
    printf '::error::%s requires minReplicas >= 1; a revision scaled to zero never reports healthy\n' "$app"
    exit 1
  fi
  # The new image is pulled by digest when the revision is created; without a managed
  # identity binding that pull fails only after a broken revision already exists.
  if ! jq -e --arg registry "$ACR_NAME.azurecr.io" \
      '.properties.configuration.registries[]? | select(.server == $registry and (.identity // "") != "")' \
      "$app_json" > /dev/null; then
    printf '::error::%s must pull from %s with a managed identity (infra/scripts/deploy-%s-app.sh binds it)\n' \
      "$app" "$ACR_NAME.azurecr.io" "$service"
    exit 1
  fi
  container="$(jq -r '.properties.template.containers[0].name' "$app_json")"
  previous_image="$(jq -r '.properties.template.containers[0].image' "$app_json")"
  if [[ "$service" == api ]]; then
    API_CONTAINER="$container"; API_PREVIOUS_IMAGE="$previous_image"
  else
    WEB_CONTAINER="$container"; WEB_PREVIOUS_IMAGE="$previous_image"
  fi
  echo "$app: running $previous_image"
done

# The browser reaches the API only through the web app's /api/* forwarder. The API's
# ingress must be internal, and the web is pointed at its actual internal FQDN
# (<app>.internal.<environment domain>), read from Azure rather than assembled.
if [[ "$(jq -r '.properties.configuration.ingress.external' "$deploy_tmp/api.app.json")" != false ]]; then
  printf '::error::%s must have internal ingress; only the web app is public (infra/bicep/services/api-app.bicep)\n' "$API_APP_NAME"
  exit 1
fi
api_fqdn="$(jq -r '.properties.configuration.ingress.fqdn // ""' "$deploy_tmp/api.app.json")"
if [[ -z "$api_fqdn" ]]; then
  printf '::error::%s has no ingress FQDN; the web app has nothing to forward /api/* to\n' "$API_APP_NAME"
  exit 1
fi
BACKEND_ORIGIN="https://${api_fqdn}"
echo "web forwards /api/* to $BACKEND_ORIGIN"
echo "::endgroup::"

echo "::group::Validate configuration against deploy/env-contract.json"
# Both services are validated before anything changes, so a broken web config cannot
# leave a half-deployed API behind.
DEPLOYMENT_SECRETS_JSON="$secrets_json" python3 scripts/deploy_env.py --service api \
  --current-app "$deploy_tmp/api.app.json" ${prune_flag[@]+"${prune_flag[@]}"} \
  --derived ENVIRONMENT=dev \
  --out "$deploy_tmp/api.env" --previous-out "$deploy_tmp/api.previous" \
  --key-vault-out "$deploy_tmp/key-vault" --emit-masks
DEPLOYMENT_SECRETS_JSON="$secrets_json" python3 scripts/deploy_env.py --service web \
  --current-app "$deploy_tmp/web.app.json" ${prune_flag[@]+"${prune_flag[@]}"} \
  --derived "BACKEND_ORIGIN=$BACKEND_ORIGIN" \
  --out "$deploy_tmp/web.env" --previous-out "$deploy_tmp/web.previous" --emit-masks
unset secrets_json
echo "::endgroup::"

# Main may have advanced while CI published and this validated. Recheck immediately
# before the first change to Azure; a GitHub API failure also stops the deploy.
main_sha="$(gh api "repos/${GITHUB_REPOSITORY}/git/ref/heads/main" --jq '.object.sha')"
if [[ "$DEPLOY_SHA" != "$main_sha" ]]; then
  printf '::error::Refusing stale deployment: %s is no longer main (%s).\n' "$DEPLOY_SHA" "$main_sha"
  exit 1
fi

echo "::group::Synchronize application secrets to Key Vault"
# --file, not --value: a value on the command line is visible to every process.
key_vault_synced=1
for secret_file in "$deploy_tmp"/key-vault/*; do
  [[ -e "$secret_file" ]] || continue
  az keyvault secret set --vault-name "$KEY_VAULT_NAME" \
    --name "$(basename "$secret_file")" --file "$secret_file" --output none
  rm -f -- "$secret_file"
done
echo "::endgroup::"

# expect_json <label> <json> <jq-filter>...: every filter must be true.
expect_json() {
  local label="$1" body="$2"
  shift 2
  for filter in "$@"; do
    if ! jq -e "$filter" <<< "$body" > /dev/null; then
      printf '::error::%s health failed: %s\n' "$label" "$filter"
      echo "$body"
      return 1
    fi
  done
}

# API first: the new web must never forward to an API that lacks its routes. Record
# each attempt before the helper runs: it can fail after changing Azure.
api_deployed=1
bash scripts/aca_rollout.sh "$API_APP_NAME" "$RESOURCE_GROUP" "$API_CONTAINER" \
  "$API_IMAGE" "$deploy_tmp/api.env"

web_deployed=1
bash scripts/aca_rollout.sh "$WEB_APP_NAME" "$RESOURCE_GROUP" "$WEB_CONTAINER" \
  "$WEB_IMAGE" "$deploy_tmp/web.env"

echo "::group::Verify the site end to end"
# /api/health through the public web URL traverses web -> BACKEND_ORIGIN -> API ->
# database in one request, and reports whether auth and AI are configured.
health="$(curl --fail --silent --show-error \
  --retry 30 --retry-delay 10 --retry-all-errors "$AZURE_WEB_URL/api/health")"
expect_json Site "$health" \
  '.status == "ok"' '.database == "ok"' '.environment == "dev"' \
  '.auth.mode == "entra"' '.auth.configured == true' '.ai.configured == true'
# The page itself renders only when the web's Entra configuration is present.
curl --fail --silent --show-error --retry 6 --retry-delay 10 --retry-all-errors \
  --output /dev/null "$WEB_URL/"
echo "::endgroup::"
