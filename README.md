# AI Tool Starter (Cookiecutter template)

An opinionated, lightweight, production-ready starter template for building
**internal AI-native web applications** on Azure.

This is a [Cookiecutter](https://cookiecutter.readthedocs.io/) template. Running
it generates a new, ready-to-run project with a Next.js frontend, a FastAPI
backend, Microsoft Entra ID auth, an Azure AI Foundry integration (mockable for
local dev), Bicep infrastructure, GitHub Actions CI/CD, tests, and docs.

## What you get

- **Frontend** — Next.js (App Router) + TypeScript, Tailwind CSS, MSAL auth,
  and a typed API client that attaches Entra access tokens to backend calls.
- **Backend** — FastAPI with JWT validation for Entra, role/group checks,
  structured logging, correlation IDs, consistent error envelopes, SQLAlchemy +
  Alembic, and a pluggable AI provider (mock / Azure AI Foundry).
- **Infra** — modular Bicep for Azure Container Apps, ACR, Key Vault, Azure SQL,
  Storage, App Insights/Log Analytics, and optional AI Search.
- **CI/CD** — GitHub Actions for CI and OIDC-based deploy to Azure.
- **Docs** — architecture, security, runbook, local-dev, and ADRs.

## Generate a project

```bash
pip install cookiecutter
cookiecutter path/to/ai-tool-starter
# or from git:
# cookiecutter https://github.com/your-org/ai-tool-starter
```

You'll be prompted for:

| Variable | Example | Purpose |
| --- | --- | --- |
| `project_name` | `Internal AI Tool` | Human-readable name |
| `project_slug` | `internal-ai-tool` | Repo/dir + resource naming |
| `python_package_name` | `internal_ai_tool` | Python package |
| `project_description` | ... | Shown in READMEs |
| `azure_location` | `eastus` | Default Azure region |
| `resource_prefix` | `aitool` | Prefix for Azure resource names |
| `entra_tenant_id` | GUID | Microsoft Entra tenant |
| `frontend_client_id` | GUID | SPA app registration |
| `backend_client_id` | GUID | API app registration |
| `backend_app_id_uri` | `api://internal-ai-tool` | API audience |
| `enable_ai_search` | `no` / `yes` | Include Azure AI Search scaffolding |

Then:

```bash
cd internal-ai-tool
cp .env.example .env
make dev          # runs frontend + backend + db locally with mock AI
```

## Prefer search-and-replace instead of Cookiecutter?

See [`TEMPLATE_USAGE.md`](./TEMPLATE_USAGE.md) for the exact list of placeholder
values to replace if you copy the generated tree by hand.

## Repository layout

```
ai-tool-starter/
  cookiecutter.json                 # template variables
  hooks/                            # pre/post generation validation
  TEMPLATE_USAGE.md
  {{cookiecutter.project_slug}}/    # <-- the generated project lives here
    apps/web/                       # Next.js frontend
    apps/api/                       # FastAPI backend
    packages/api-client/            # shared typed API client types
    infra/bicep/                    # Azure infrastructure
    docs/                           # architecture, security, runbook, ADRs
    .github/workflows/              # CI + deploy
```
