#!/usr/bin/env bash
# Local development: PostgreSQL in Docker, the API and the web app natively with hot
# reload. Reads .env (created from .env.example on first run). Ctrl+C stops both.
#
#   make dev        (after `make install`)
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [[ ! -x .venv/bin/python ]]; then
  echo "error: run 'make install' first" >&2
  exit 1
fi
if [[ ! -f .env ]]; then
  cp .env.example .env
  echo "created .env from .env.example"
fi

# Export everything in .env to both processes.
set -a
# shellcheck disable=SC1091
. ./.env
set +a

docker compose up --detach --wait db
(cd api && ../.venv/bin/alembic upgrade head)

trap 'kill 0' EXIT
(cd api && exec ../.venv/bin/uvicorn app.main:app --reload --port 8000) &
(cd web && exec npm run dev) &
echo
echo "web: http://localhost:3000   api docs: http://localhost:8000/docs"
wait
