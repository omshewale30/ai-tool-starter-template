# Local development

The app runs fully locally with **no Azure dependencies**: mock AI and disabled
auth by default.

## Prerequisites

- **Docker** (for `make dev` / docker-compose)
- **Node 20 LTS or 22 LTS** and **npm** (frontend)
- **Python 3.11+** (backend)
- Optional: **make** (shortcuts), **Azure CLI** (only for real Azure/Foundry)

## Quick start (everything in Docker)

```bash
cp .env.example .env
make dev            # or: docker compose up --build
```

- Frontend: http://localhost:3000
- Backend: http://localhost:8000 (OpenAPI docs at `/docs`)
- Database: SQL Server on localhost:1433
- The API container runs `alembic upgrade head` on startup, so the local schema
  is created automatically.

## Run services individually

Backend:

```bash
cd apps/api
python3.11 -m venv .venv && source .venv/bin/activate
pip install -e ".[dev]"
export AI_PROVIDER=mock AUTH_MODE=disabled DATABASE_URL="sqlite+pysqlite:///./local.db"
alembic upgrade head
uvicorn app.main:app --reload
```

Frontend:

```bash
cd apps/web
cp .env.local.example .env.local
npm install
npm run dev
```

## Mock AI mode

`AI_PROVIDER=mock` (the default locally) uses `MockAIProvider`, which echoes a
deterministic response. No credentials or network are required, and the backend
test suite relies on it. Switch to `AI_PROVIDER=foundry` only when you have a
real Azure AI Foundry endpoint and credentials (`az login`).

## Auth-disabled mode ⚠️

`AUTH_MODE=disabled` (backend) and `NEXT_PUBLIC_AUTH_DISABLED=true` (frontend)
bypass Microsoft Entra sign-in so you can develop without app registrations.

**This is for local development only.** It injects a fake admin principal, logs a
warning on every request, and the UI shows a persistent warning banner. Never use
it in a deployed environment. To exercise real auth locally, set both flags to
the enabled values and provide real Entra `NEXT_PUBLIC_ENTRA_*` / `AZURE_TENANT_ID`
values.

## Running tests

```bash
# Backend (mock AI + in-memory SQLite; no Azure needed)
cd apps/api && pytest

# Frontend unit/component tests
cd apps/web && npm run test

# Frontend E2E smoke test (installs a browser on first run)
cd apps/web && npx playwright install --with-deps && npm run test:e2e
```

## Common local issues

| Issue | Fix |
| --- | --- |
| Port 3000/8000/1433 in use | Stop the conflicting process or change the mapped port in `docker-compose.yml`. |
| SQL container slow to accept connections | It has a health check; the API waits for it. First start can take ~30s. |
| `pyodbc` / ODBC driver errors locally | Use the SQLite `DATABASE_URL` for pure-local runs, or run the backend via Docker (the image bundles the driver). |
| Frontend can't reach backend | Confirm `NEXT_PUBLIC_API_BASE_URL` and that the API is running / CORS origin matches. |
| MSAL errors with auth enabled | Ensure the redirect URI is registered and the API scope is consented. See the runbook. |
| Changes to `NEXT_PUBLIC_*` not taking effect | These inline at build time; restart `npm run dev` after editing `.env.local`. |
