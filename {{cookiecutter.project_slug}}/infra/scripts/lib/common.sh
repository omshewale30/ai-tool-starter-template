#!/usr/bin/env bash

require_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "error: required command not found: $cmd" >&2
    exit 1
  fi
}

default_state_file() {
  local script_root="$1"
  local resource_group="$2"
  echo "$script_root/../state/${resource_group}.json"
}

ensure_state_file() {
  local state_file="$1"
  mkdir -p "$(dirname "$state_file")"
  if [[ ! -f "$state_file" ]]; then
    printf '{"services":{}}\n' >"$state_file"
  fi
}

resolve_location() {
  local resource_group="$1"
  local location="${2:-}"

  if [[ -n "$location" ]]; then
    echo "$location"
    return
  fi

  az group show --name "$resource_group" --query location -o tsv
}

resolve_required_value() {
  local explicit_value="$1"
  local state_file="$2"
  local state_query="$3"
  local arg_hint="$4"

  if [[ -n "$explicit_value" ]]; then
    echo "$explicit_value"
    return
  fi

  local state_value
  state_value="$(jq -er "$state_query" "$state_file" 2>/dev/null || true)"
  if [[ -z "$state_value" || "$state_value" == "null" ]]; then
    echo "error: missing required dependency. Provide ${arg_hint} or populate ${state_query} in $state_file." >&2
    exit 1
  fi

  echo "$state_value"
}

resolve_optional_value() {
  local explicit_value="$1"
  local state_file="$2"
  local state_query="$3"

  if [[ -n "$explicit_value" ]]; then
    echo "$explicit_value"
    return
  fi

  jq -er "$state_query" "$state_file" 2>/dev/null || true
}

new_deployment_name() {
  local service_name="$1"
  local environment_name="$2"
  echo "${service_name}-${environment_name}-$(date -u +%Y%m%d%H%M%S)"
}

extract_outputs_json() {
  local deployment_json="$1"
  printf '%s' "$deployment_json" | jq '.properties.outputs // {} | with_entries(.value = .value.value)'
}

save_service_outputs() {
  local state_file="$1"
  local service_name="$2"
  local resource_group="$3"
  local environment_name="$4"
  local resource_prefix="$5"
  local deployment_json="$6"

  local outputs_json
  outputs_json="$(extract_outputs_json "$deployment_json")"

  local tmp_file
  tmp_file="$(mktemp)"

  jq \
    --arg service "$service_name" \
    --arg rg "$resource_group" \
    --arg env "$environment_name" \
    --arg prefix "$resource_prefix" \
    --argjson outputs "$outputs_json" \
    '
      .resourceGroup = $rg
      | .environment = $env
      | .resourcePrefix = $prefix
      | (.services //= {})
      | .services[$service] = $outputs
    ' "$state_file" >"$tmp_file"

  mv "$tmp_file" "$state_file"
}

print_outputs() {
  local deployment_json="$1"
  extract_outputs_json "$deployment_json" | jq .
}

# Container apps are created once by infra; afterwards scripts/cd.sh owns their image
# and env. Re-running the Bicep would reset both (to the bootstrap image), so refuse
# unless the caller asked for it explicitly.
refuse_if_app_exists() {
  local app_name="$1"
  local resource_group="$2"
  local recreate="$3"

  if [[ "$recreate" == "true" ]]; then
    return
  fi
  if az containerapp show --name "$app_name" --resource-group "$resource_group" --output none 2>/dev/null; then
    echo "error: $app_name already exists. CD (scripts/cd.sh) owns its image and env now;" >&2
    echo "       re-running this would reset both. Pass --recreate to do it anyway, then" >&2
    echo "       re-run the CD workflow (workflow_dispatch) to redeploy main." >&2
    exit 1
  fi
}

# Prints `present` or `missing` for a Key Vault secret (never its value). Owner and
# Contributor grant no data access to an RBAC vault, and a fresh role assignment takes
# minutes to apply, so "forbidden" is retried for a while and then reported as what
# it is, never mistaken for "missing".
kv_secret_state() {
  local vault="$1" name="$2" output attempt
  for attempt in $(seq 1 12); do
    if output="$(az keyvault secret show --vault-name "$vault" --name "$name" --query id -o tsv 2>&1)"; then
      echo present
      return
    fi
    case "$output" in
      *SecretNotFound*|*"was not found"*)
        echo missing
        return
        ;;
      *Forbidden*|*"not authorized"*|*"does not have secrets get permission"*)
        echo "waiting for Key Vault access to apply ($attempt/12)..." >&2
        sleep 10
        ;;
      *)
        echo "error: could not read Key Vault secret $name: $output" >&2
        exit 1
        ;;
    esac
  done
  echo "error: you have no data access to Key Vault $vault. Re-run deploy-key-vault.sh" >&2
  echo "       (it grants the signed-in user Key Vault Secrets Officer) and try again." >&2
  exit 1
}
