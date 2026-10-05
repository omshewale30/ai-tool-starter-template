#!/usr/bin/env bash
# Build every image for $IMAGE_TAG in ACR as <prefix>-<service>:$IMAGE_TAG, then pull the
# exact digests that were pushed and smoke-test them together (scripts/smoke.sh).
# Publishes only; it never touches a container app. Promotion is scripts/cd.sh, which
# deploys these same digests, so the artifact that passed this gate is the one that ships.
#
# Part of the FO-AI repository script contract (scripts/ci.sh, scripts/publish.sh,
# scripts/cd.sh); see the FO-AI/automation README.
#
# Needs: az signed in (OIDC in CI, `az login` on a laptop) with build and pull rights on
#        ACR_NAME; docker; jq; ACR_NAME; IMAGE_TAG (a full commit SHA).
#        IMAGE_PREFIX defaults to the repository name (the contract's <repo>-<service>).
#        No build args: both images read their configuration at run time, so one image
#        serves every environment.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

IMAGE_PREFIX="${IMAGE_PREFIX:-${GITHUB_REPOSITORY##*/}}"
for name in ACR_NAME IMAGE_TAG IMAGE_PREFIX; do
  if [[ -z "${!name:-}" ]]; then
    printf '::error::Missing publish setting: %s (set it as a repository variable)\n' "$name"
    exit 1
  fi
done
if [[ ! "$IMAGE_TAG" =~ ^[0-9a-f]{40}$ ]]; then
  echo '::error::IMAGE_TAG must be a full commit SHA; cd.sh looks images up by that tag'
  exit 1
fi

for service in api web; do
  echo "::group::Build ${IMAGE_PREFIX}-${service}:${IMAGE_TAG} in ACR"
  az acr build --registry "$ACR_NAME" --image "${IMAGE_PREFIX}-${service}:${IMAGE_TAG}" "$service"
  echo "::endgroup::"
done

# The registry's word for each digest is exactly what cd.sh will ask for.
echo "::group::Resolve the pushed digests"
for service in api web; do
  digest="$(az acr repository show --name "$ACR_NAME" \
    --image "${IMAGE_PREFIX}-${service}:${IMAGE_TAG}" --query digest -o tsv)"
  if [[ ! "$digest" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    printf '::error::%s-%s:%s did not resolve to a sha256 digest (got %q)\n' \
      "$IMAGE_PREFIX" "$service" "$IMAGE_TAG" "$digest"
    exit 1
  fi
  printf -v "$(tr '[:lower:]' '[:upper:]' <<< "$service")_IMAGE" '%s' \
    "${ACR_NAME}.azurecr.io/${IMAGE_PREFIX}-${service}@${digest}"
done
echo "api: $API_IMAGE"
echo "web: $WEB_IMAGE"
echo "::endgroup::"

echo "::group::Pull the pushed digests"
az acr login --name "$ACR_NAME"
docker pull --quiet "$API_IMAGE"
docker pull --quiet "$WEB_IMAGE"
echo "::endgroup::"

report="$(mktemp "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/smoke.XXXXXX")"
trap 'rm -f -- "$report"' EXIT
bash scripts/smoke.sh "$API_IMAGE" "$WEB_IMAGE" "$report"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    printf '### Published and smoke-tested images\n\n| | |\n|---|---|\n'
    printf '| tag | `%s` |\n| api | `%s` |\n| web | `%s` |\n\n' "$IMAGE_TAG" "$API_IMAGE" "$WEB_IMAGE"
    printf '```json\n%s\n```\n' "$(jq . "$report")"
  } >> "$GITHUB_STEP_SUMMARY"
fi
