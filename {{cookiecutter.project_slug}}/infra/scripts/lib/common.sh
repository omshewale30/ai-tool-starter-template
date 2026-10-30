#!/usr/bin/env bash

TERRAFORM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../terraform" && pwd)"

require_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "error: required command not found: $cmd" >&2
    exit 1
  fi
}

# Prints the outputs of one Terraform root (e.g. envs/dev) as JSON {name: value}.
# Needs `terraform init` to have run there (it reads the remote state).
terraform_outputs() {
  local root="$1" json
  if ! json="$(terraform -chdir="$TERRAFORM_DIR/$root" output -json)"; then
    echo "error: could not read Terraform outputs of $root. Run terraform init" >&2
    echo "       -backend-config=../../backend.hcl and apply there first (docs/runbook.md)." >&2
    exit 1
  fi
  printf '%s' "$json" | jq 'with_entries(.value = .value.value)'
}

# Reads one value from terraform_outputs JSON; fails with a hint if it is missing.
output_value() {
  local outputs="$1" query="$2" value
  value="$(printf '%s' "$outputs" | jq -er "$query" 2>/dev/null || true)"
  if [[ -z "$value" || "$value" == "null" ]]; then
    echo "error: Terraform output $query is missing; apply that root first." >&2
    exit 1
  fi
  printf '%s' "$value"
}
