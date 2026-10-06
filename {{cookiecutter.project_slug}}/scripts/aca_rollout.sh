#!/usr/bin/env bash
# Roll one container app onto an image and env, then wait for that revision to be healthy.
#
#   aca_rollout.sh <app> <resource-group> <container> <image> <env-args-file>
#
# <env-args-file> holds NUL-delimited KEY=VALUE records (rendered by scripts/deploy_env.py)
# and REPLACES the container's env: --set-env-vars merges and never removes, so a key
# deleted from the contract would live on the app forever. An empty file clears the env.
#
# Called by scripts/cd.sh for each forward rollout and for each rollback, so the restore
# path is the same code as the deploy path — there is no separate, less-tested branch to
# get wrong during an incident. Also runnable by hand against dev.
#
# Every mutating `az` call passes `-o none`: an unguarded `az containerapp update` prints
# the full app JSON, environment variable values included, to the log.
set -euo pipefail

APP="${1:?app name}"
GROUP="${2:?resource group}"
CONTAINER="${3:?container name}"
IMAGE="${4:?image reference}"
ENV_ARGS_FILE="${5:?env args file}"

# The API runs its migrations before it binds, which can take a while on a large
# schema change; ten minutes covers that with room to spare.
POLL_SECONDS="${ROLLOUT_POLL_SECONDS:-10}"
POLL_LIMIT="${ROLLOUT_POLL_LIMIT:-60}"

echo "::group::Roll out ${APP}"
echo "image: ${IMAGE}"

ENV_ARGS=()
while IFS= read -r -d '' record; do
  ENV_ARGS+=("$record")
done < <(cat "$ENV_ARGS_FILE"; [[ -s "$ENV_ARGS_FILE" ]] && printf '\0')

if (( ${#ENV_ARGS[@]} )); then
  az containerapp update --name "$APP" --resource-group "$GROUP" \
    --container-name "$CONTAINER" --image "$IMAGE" \
    --replace-env-vars "${ENV_ARGS[@]}" --output none
else
  az containerapp update --name "$APP" --resource-group "$GROUP" \
    --container-name "$CONTAINER" --image "$IMAGE" \
    --remove-all-env-vars --output none
fi
echo "env: ${#ENV_ARGS[@]} variable(s), replaced"

REVISION="$(az containerapp show --name "$APP" --resource-group "$GROUP" \
  --query properties.latestRevisionName -o tsv)"
echo "waiting on revision: ${REVISION}"

for (( attempt = 1; attempt <= POLL_LIMIT; attempt++ )); do
  # Read by name, not position: these fields are each optional, and a tab-separated
  # read would shift a value into the wrong variable when one is empty.
  revision_json="$(az containerapp revision show --name "$APP" --resource-group "$GROUP" \
    --revision "$REVISION" -o json)"
  health="$(jq -r '.properties.healthState // ""' <<< "$revision_json")"
  running="$(jq -r '.properties.runningState // ""' <<< "$revision_json")"
  provisioning="$(jq -r '.properties.provisioningState // ""' <<< "$revision_json")"
  ready="$(az containerapp show --name "$APP" --resource-group "$GROUP" \
    --query properties.latestReadyRevisionName -o tsv)"
  echo "  [${attempt}/${POLL_LIMIT}] health=${health} running=${running} provisioning=${provisioning} ready=${ready}"

  # Fail fast. A revision that has already lost does not recover by waiting, and
  # waiting out the timeout delays the rollback by ten minutes.
  case "${health}/${running}/${provisioning}" in
    Unhealthy/*|*/Failed/*|*/Degraded/*|*/*/Failed)
      echo "::error::${APP}: revision ${REVISION} failed (health=${health} running=${running} provisioning=${provisioning})"
      echo "::endgroup::"
      exit 1
      ;;
  esac

  # Container Apps names a revision latestReady only once it can serve. An absent
  # runningState is unknown rather than failed; one that is reported must say Running.
  if [[ "$health" == Healthy && "$ready" == "$REVISION" ]] \
      && [[ -z "$running" || "$running" == Running ]]; then
    echo "${APP}: revision ${REVISION} is healthy and serving"
    echo "::endgroup::"
    exit 0
  fi

  sleep "$POLL_SECONDS"
done

echo "::error::${APP}: revision ${REVISION} did not become healthy within $(( POLL_LIMIT * POLL_SECONDS ))s"
echo "::endgroup::"
exit 1
