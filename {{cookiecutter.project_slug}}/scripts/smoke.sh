#!/usr/bin/env bash
# Run an API image and a web image together and assert what a deploy will assert.
#
#   smoke.sh <api-image> <web-image> [report.json]
#
# scripts/publish.sh runs this on the exact digests it pushed, so the artifact that
# passed this gate is the artifact scripts/cd.sh promotes. Also runnable locally on
# images built with plain `docker build` (no build args: both images are
# environment-agnostic). scripts/verify-template.sh --docker does exactly that.
#
# The topology matches Azure: only the web is published; it forwards /api/* to the API
# over a private network (BACKEND_ORIGIN). The web gets a client id that exists nowhere at
# build time; finding it in the rendered page proves configuration is read at run time.
#
# Needs docker, curl, jq. No Azure, no Entra: auth is configured but never exercised.
set -euo pipefail

API_IMAGE="${1:?api image}"
WEB_IMAGE="${2:?web image}"
REPORT="${3:-}"

RUN_ID="smoke-$$"
WEB_PORT="${SMOKE_WEB_PORT:-13000}"
WEB_URL="http://127.0.0.1:${WEB_PORT}"
CLIENT_ID="smoke-client-${RUN_ID}"
DB_PASSWORD="smokeonly${RUN_ID//-/}"

cleanup() {
  local status=$?
  trap - EXIT
  set +e
  if (( status != 0 )); then
    echo '::group::Smoke container logs'
    for service in db api web; do
      echo "--- ${service}"
      docker logs "${RUN_ID}-${service}" 2>&1 | tail -n 100
    done
    echo '::endgroup::'
  fi
  docker rm --force "${RUN_ID}-web" "${RUN_ID}-api" "${RUN_ID}-db" > /dev/null 2>&1
  docker network rm "$RUN_ID" > /dev/null 2>&1
  exit "$status"
}
trap cleanup EXIT

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

echo "::group::Check the API image's packaged files"
# Prompts ship as package data; a missing file would only fail on the first chat.
docker run --rm "$API_IMAGE" python -c '
from importlib import resources
from app.prompts import load_prompt
names = [f.name[:-3] for f in resources.files("app.prompts").iterdir() if f.name.endswith(".md")]
assert names, "no prompt files packaged"
for name in names:
    load_prompt(name)
print("prompts packaged:", ", ".join(sorted(names)))
'
echo "::endgroup::"

echo "::group::Start database, API, and web"
docker network create "$RUN_ID" > /dev/null
docker run --detach --name "${RUN_ID}-db" --network "$RUN_ID" --network-alias db \
  --env POSTGRES_USER=app --env POSTGRES_PASSWORD="$DB_PASSWORD" --env POSTGRES_DB=appdb \
  postgres:16-alpine > /dev/null
for _ in $(seq 1 30); do
  docker exec "${RUN_ID}-db" pg_isready -U app -d appdb > /dev/null 2>&1 && break
  sleep 2
done
docker exec "${RUN_ID}-db" pg_isready -U app -d appdb > /dev/null

# Deployed shape (Entra auth, a non-local environment) with the mock AI provider. The
# image's own CMD migrates against a real Postgres. The API publishes no port, as in
# Azure where its ingress is internal.
docker run --detach --name "${RUN_ID}-api" --network "$RUN_ID" --network-alias api \
  --env ENVIRONMENT=smoke \
  --env AUTH_MODE=entra \
  --env AZURE_TENANT_ID=smoke-tenant \
  --env ENTRA_BACKEND_CLIENT_ID=smoke-backend \
  --env ENTRA_BACKEND_APP_ID_URI=api://smoke-backend \
  --env AI_PROVIDER=mock \
  --env DATABASE_URL="postgresql+psycopg://app:${DB_PASSWORD}@db:5432/appdb" \
  "$API_IMAGE" > /dev/null
docker run --detach --name "${RUN_ID}-web" --network "$RUN_ID" \
  --publish "127.0.0.1:${WEB_PORT}:3000" \
  --env BACKEND_ORIGIN=http://api:8000 \
  --env ENTRA_CLIENT_ID="$CLIENT_ID" \
  --env ENTRA_TENANT_ID=smoke-tenant \
  --env ENTRA_API_SCOPE=api://smoke-backend/access_as_user \
  "$WEB_IMAGE" > /dev/null
echo "::endgroup::"

echo "::group::Assert health through the web"
# The web's own probe endpoint (Container Apps liveness/readiness).
curl --fail --silent --show-error --retry 30 --retry-delay 2 --retry-all-errors \
  --output /dev/null "$WEB_URL/healthz"
health="$(curl --fail --silent --show-error \
  --retry 60 --retry-delay 2 --retry-all-errors "$WEB_URL/api/health")"
echo "health: $health"
expect_json Site "$health" \
  '.status == "ok"' '.database == "ok"' '.environment == "smoke"' \
  '.auth.mode == "entra"' '.auth.configured == true' '.ai.configured == true'

# Without a token the API must refuse; the forwarder must not hide that.
status="$(curl --silent --output /dev/null --write-out '%{http_code}' "$WEB_URL/api/v1/me")"
if [[ "$status" != 401 ]]; then
  printf '::error::GET /api/v1/me without a token returned %s, expected 401\n' "$status"
  exit 1
fi

page="$(curl --fail --silent --show-error --retry 6 --retry-delay 2 --retry-all-errors "$WEB_URL/")"
if [[ "$page" != *"$CLIENT_ID"* ]]; then
  echo '::error::The landing page does not carry the runtime ENTRA_CLIENT_ID; configuration is baked in at build time'
  exit 1
fi
echo "unauthenticated API call refused; landing page carries the runtime client id"
echo "::endgroup::"

if [[ -n "$REPORT" ]]; then
  jq -n --arg api_image "$API_IMAGE" --arg web_image "$WEB_IMAGE" --argjson health "$health" \
    '{api_image: $api_image, web_image: $web_image, health: $health,
      runtime_config_reaches_page: true, unauthenticated_api_refused: true}' > "$REPORT"
fi
