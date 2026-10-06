# {{ cookiecutter.project_name }} — API (FastAPI)

## Layout

```
app/
  main.py                # app factory: logging, telemetry, middleware, routers
  core/                  # settings, logging, JWT validation, errors, middleware
  api/v1/                # router + routes (me, chat, admin{% if cookiecutter.enable_ai_search == "yes" %}, rag{% endif %}); health at /health/* and /api/health
  models/                # SQLAlchemy models (AuditEvent)
  schemas/               # Pydantic request/response models
  prompts/               # prompt templates (*.md), load_prompt/render_prompt
  services/
    ai/                  # AIProvider (mock, Azure OpenAI), streaming helper, AI dependency
{%- if cookiecutter.enable_ai_search == "yes" %}
    search/              # Azure AI Search retrieval for RAG
{%- endif %}
    telemetry/           # Azure Monitor setup, AISpan
    storage/             # Blob Storage wrapper
    identity/            # CurrentUser / AdminUser dependencies
    audit.py             # record important events
  db/                    # engine/session, base, Alembic migrations
  tests/                 # pytest (mock AI, in-memory SQLite)
scripts/export_openapi.py  # OpenAPI JSON for the web's generated types
```

## Run

From the repository root, `make install` then `make dev` (see
[../docs/local-development.md](../docs/local-development.md)). Tests:

```bash
make test-api        # or: cd api && ../.venv/bin/pytest
```

Interactive docs at <http://localhost:8000/docs> (local and test environments only).

## Settings

All settings are environment variables, typed in `app/core/config.py`; see the
repository-root `.env.example`. In Azure they are applied by CD according to
`deploy/env-contract.json`. Key ones: `AUTH_MODE`, `AZURE_TENANT_ID`,
`ENTRA_BACKEND_CLIENT_ID`, `ENTRA_BACKEND_APP_ID_URI`, `AI_PROVIDER`,
`AZURE_AI_FOUNDRY_*` ([../docs/ai.md](../docs/ai.md)), `DATABASE_URL` (PostgreSQL;
SQLite in tests).

## Migrations

```bash
make migration m="add my table"   # autogenerate from models; review the file
make migrate                      # apply
```

In Azure, the image runs `alembic upgrade head` before serving.
