#!/usr/bin/env bash
# Generates projects from this Cookiecutter template and proves they work.
#
#   bash scripts/verify-template.sh                 # both variants
#   bash scripts/verify-template.sh --variant no    # AI Search disabled only
#   bash scripts/verify-template.sh --docker        # also build images + smoke test
#   bash scripts/verify-template.sh --keep          # keep generated projects
#
# For each variant this renders the template, commits the result to a fresh git
# repo (CI checks diff against committed generated files), installs
# dependencies, and runs the generated project's own `scripts/ci.sh` checks,
# Bicep compilation, and `docker compose config`.
#
# Env: PYTHON (default python3.11), OUT_DIR (default: a temp dir).
set -euo pipefail

TEMPLATE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON="${PYTHON:-python3.11}"
VARIANTS=(no yes)
RUN_DOCKER=0
KEEP=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --variant) VARIANTS=("$2"); shift 2 ;;
    --docker) RUN_DOCKER=1; shift ;;
    --keep) KEEP=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

cookiecutter_cmd() {
  if command -v cookiecutter >/dev/null 2>&1; then
    cookiecutter "$@"
  elif command -v uvx >/dev/null 2>&1; then
    uvx cookiecutter "$@"
  else
    "$PYTHON" -m cookiecutter "$@"
  fi
}

OUT_DIR="${OUT_DIR:-$(mktemp -d)}"
mkdir -p "$OUT_DIR"
if [[ "$KEEP" == "0" ]]; then
  trap 'rm -rf "$OUT_DIR"' EXIT
fi

verify_variant() {
  local search="$1"
  local slug="verify-search-${search}"
  local project="$OUT_DIR/$slug"

  log "[$slug] render template"
  rm -rf "$project"
  cookiecutter_cmd --no-input --output-dir "$OUT_DIR" "$TEMPLATE_ROOT" \
    project_name="Verify Search ${search}" \
    project_slug="$slug" \
    enable_ai_search="$search"

  if grep -rIl --exclude-dir=node_modules --exclude-dir=.git 'cookiecutter\.' "$project" >/dev/null; then
    echo "error: unrendered cookiecutter placeholders remain:" >&2
    grep -rIn --exclude-dir=node_modules --exclude-dir=.git 'cookiecutter\.' "$project" >&2
    return 1
  fi

  # Opt-out variants must not carry the optional code paths.
  if [[ "$search" == "no" && -e "$project/api/app/services/search" ]]; then
    echo "error: enable_ai_search=no but api/app/services/search was generated" >&2
    return 1
  fi
  if [[ "$search" == "yes" && ! -e "$project/api/app/services/search" ]]; then
    echo "error: enable_ai_search=yes but api/app/services/search is missing" >&2
    return 1
  fi

  (
    cd "$project"
    git init -q
    git add -A
    git -c user.name=verify -c user.email=verify@localhost commit -qm "generated"

    log "[$slug] install dependencies"
    "$PYTHON" -m venv .venv
    # shellcheck disable=SC1091
    . .venv/bin/activate
    python -m pip install -q --upgrade pip
    python -m pip install -q -e "./api[dev]"
    if [[ -f web/package-lock.json ]]; then
      npm --prefix web ci --no-audit --no-fund
    else
      npm --prefix web install --no-audit --no-fund
    fi

    log "[$slug] scripts/ci.sh backend"
    bash scripts/ci.sh backend
    log "[$slug] scripts/ci.sh frontend"
    bash scripts/ci.sh frontend

    log "[$slug] bicep build"
    if command -v az >/dev/null 2>&1 && az bicep version >/dev/null 2>&1; then
      while IFS= read -r -d '' file; do
        az bicep build --only-show-errors --file "$file" --stdout >/dev/null
      done < <(find infra/bicep -name '*.bicep' -print0)
    else
      echo "skipped: az bicep is not available"
    fi

    log "[$slug] docker compose config"
    if command -v docker >/dev/null 2>&1; then
      docker compose config --quiet
    else
      echo "skipped: docker is not available"
    fi

    if [[ "$RUN_DOCKER" == "1" ]]; then
      log "[$slug] build images + smoke test"
      docker build -q -t "$slug-api:verify" api >/dev/null
      docker build -q -t "$slug-web:verify" web >/dev/null
      if [[ -f scripts/smoke.sh ]]; then
        IMAGE_PREFIX="$slug" bash scripts/smoke.sh "$slug-api:verify" "$slug-web:verify"
      else
        echo "skipped: scripts/smoke.sh does not exist yet"
      fi
    fi

    # The checks must not leave generated files out of date.
    if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
      echo "error: checks modified tracked files:" >&2
      git status --short --untracked-files=no >&2
      return 1
    fi
  )
  log "[$slug] OK"
}

for variant in "${VARIANTS[@]}"; do
  verify_variant "$variant"
done

log "All variants passed (output: $OUT_DIR)"
