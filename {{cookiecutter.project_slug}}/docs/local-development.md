# Local development

## Prerequisites

- Python 3.11, Node.js 22, Docker (for PostgreSQL)
- Optional: Azure CLI (`az login`) to use real Azure OpenAI from your laptop

## First run

```bash
make install   # creates .venv, installs the API (editable) and web dependencies
make dev       # creates .env from .env.example on first run
```

`make dev` (`scripts/dev.sh`) starts PostgreSQL in Docker, applies migrations, and
runs the API on <http://localhost:8000> (docs at `/docs`) and the web app on
<http://localhost:3000>, both with hot reload. The web app forwards `/api/*` to the
API exactly as it does in Azure.

Defaults in `.env`: `AUTH_MODE=disabled` + `NEXT_PUBLIC_AUTH_DISABLED=true` (you are a
fake "Local Developer" admin, with a warning banner) and `AI_PROVIDER=mock` (answers
echo your prompt). Nothing in Azure is touched.

Prefer containers? `make up` runs the API image, the web app (`next dev`), and
PostgreSQL with docker compose; `make down` removes them and the data volume.

## Using the real AI models

1. `az login` with an account that has **Cognitive Services OpenAI User** on UNC's
   Azure OpenAI resource (ask the resource owners; see [ai.md](ai.md)).
2. In `.env`: `AI_PROVIDER=foundry`, `AZURE_AI_FOUNDRY_ENDPOINT`,
   `AZURE_AI_FOUNDRY_DEPLOYMENT_NAME` (and `..._EMBEDDING_DEPLOYMENT_NAME` if you use
   embeddings).
3. Restart `make dev`. `DefaultAzureCredential` uses your `az login` session.

## Using real sign-in

1. Register `http://localhost:3000/auth` as a **SPA** redirect URI on the web app
   registration (see [runbook.md](runbook.md#app-registrations)).
2. In `.env`: `AUTH_MODE=entra`, `NEXT_PUBLIC_AUTH_DISABLED=false`, and the
   `AZURE_TENANT_ID`, `ENTRA_BACKEND_*`, and `ENTRA_*` values.
3. Restart `make dev`.

## Tests and checks

| Command | What |
| --- | --- |
| `make test-api` | pytest (mock AI, in-memory SQLite) |
| `make test-web` | Vitest component/unit tests |
| `make e2e` | Playwright: real API behind a production web build |
| `make lint` / `make fmt` | ruff + eslint / ruff format |
| `make check` | Exactly what CI's checks run (`scripts/ci.sh backend` + `frontend`), including the deploy-script tests and the generated-types check |

## Everyday tasks

- **Changed an API route or schema?** `make generate-api` and commit
  `web/src/lib/api/schema.ts` (CI fails if it is stale).
- **Changed a model?** `make migration m="describe the change"`, review the file in
  `api/app/db/migrations/versions/`, then `make migrate`.
- **Added a setting?** Field in `api/app/core/config.py`, entry in `.env.example`,
  owner in `deploy/env-contract.json` (CI checks the last one).

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `make dev` says to run `make install` | Create the venv first: `make install` |
| Web shows "The API is unreachable" | The API isn't running on `BACKEND_ORIGIN` (default `http://127.0.0.1:8000`); check the `make dev` output |
| `Entra is not configured` error page | Sign-in is enabled but `ENTRA_CLIENT_ID`/`ENTRA_TENANT_ID`/`ENTRA_API_SCOPE` are empty, or set `NEXT_PUBLIC_AUTH_DISABLED=true` |
| `AUTH_MODE=disabled is allowed only when ENVIRONMENT is 'local' or 'test'` | Set `ENVIRONMENT=local` in `.env` |
| 401 from the API with real sign-in | Token audience or version mismatch: the API app registration must issue v2 tokens (`requestedAccessTokenVersion: 2`) and `ENTRA_BACKEND_APP_ID_URI` must match |
| AI calls return 502 | Check the API log; usually a missing role on the Azure OpenAI resource or a wrong deployment name |
| Port already in use | Stop the other process, or change ports in `scripts/dev.sh` |
