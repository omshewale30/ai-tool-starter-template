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
