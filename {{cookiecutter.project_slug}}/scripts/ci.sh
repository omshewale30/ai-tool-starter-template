#!/usr/bin/env bash
# Runs one named CI check. Called by .github/workflows/ci.yml through the FO-AI
# reusable CI, and by developers locally (`make check`).
#
#   bash scripts/ci.sh backend
#   bash scripts/ci.sh frontend
#
# Contract (FO-AI/automation): no cloud access, no secrets, dependencies are
# installed by the caller. Test-only settings are set here so a check behaves
# the same on a laptop as on a runner.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Mock AI, bypassed auth, in-memory database: no Azure or network needed.
export ENVIRONMENT=test
export AI_PROVIDER=mock
export AUTH_MODE=disabled
export DATABASE_URL="sqlite+pysqlite:///:memory:"

check_backend() {
  (
    cd api
    ruff check app
    pytest
  )
}

check_frontend() {
  (
    cd web
    # The committed API types must match the API (needs the API's Python deps).
    npm run generate:api
    git diff --exit-code -- src/lib/api/schema.ts || {
      echo "error: web/src/lib/api/schema.ts is stale. Run 'npm run generate:api' in web/ and commit it." >&2
      exit 1
    }
    npm run lint
    npm run typecheck
    npm test
    npm run build
  )
}

case "${1:-}" in
  backend) check_backend ;;
  frontend) check_frontend ;;
  *)
    echo "usage: $0 {backend|frontend}" >&2
    exit 2
    ;;
esac
