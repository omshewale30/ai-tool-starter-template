# {{ cookiecutter.project_name }} — backend (FastAPI)

## Layout

```
app/
  main.py                # app factory + wiring
  core/                  # config, logging, security (JWT), errors, middleware
  api/v1/                # router + routes (health, me, chat, admin)
  models/                # SQLAlchemy models (AuditEvent)
  schemas/               # Pydantic request/response models
  services/
    ai/                  # AIProvider abstraction: mock + Azure Foundry
    storage/             # Blob Storage wrapper
    search/              # Azure AI Search wrapper (optional)
    identity/            # auth dependencies (current_user, require_admin)
    audit.py             # record important events
  db/                    # engine/session, declarative base, Alembic migrations
  tests/                 # pytest suite (mock AI, in-memory DB)
```

## Run locally

```bash
python3.11 -m venv .venv && source .venv/bin/activate
pip install -e ".[dev]"

# Tests need no DB or Azure creds (SQLite in-memory + mock AI):
pytest

# Run the server (uses .env at the repo root or process env):
export AI_PROVIDER=mock AUTH_MODE=disabled DATABASE_URL="sqlite+pysqlite:///./local.db"
alembic upgrade head
uvicorn app.main:app --reload
```

Interactive API docs: http://localhost:8000/docs — OpenAPI JSON at
`/openapi.json`.

## Key environment variables

See the repo-root `.env.example`. The most important:

- `AI_PROVIDER` — `mock` (default) or `foundry`.
- `AUTH_MODE` — `disabled` (local only) or `entra`.
- `AZURE_TENANT_ID`, `ENTRA_BACKEND_CLIENT_ID`, `ENTRA_BACKEND_APP_ID_URI`.
- `ADMIN_GROUP_ID` — group/role granting `/api/v1/admin/*`.
- `DATABASE_URL` — SQLAlchemy URL (Azure SQL in prod).

## Migrations

```bash
alembic revision --autogenerate -m "add my table"
alembic upgrade head
```
