# AI Tool Starter (UNC Finance and Operations)

A [Cookiecutter](https://cookiecutter.readthedocs.io/) template for UNC-Chapel Hill
Finance and Operations AI tools. One command gives you a working, tested, deployable
app: a Next.js web app and a FastAPI API with Entra ID (Onyen) sign-in, UNC's
Azure-hosted OpenAI models, PostgreSQL, Azure Container Apps, and the standard
[FO-AI/automation](https://github.com/FO-AI/automation) CI/CD pipeline.

## Create a tool

```bash
uvx cookiecutter gh:omshewale30/ai-tool-starter-template
# or: pipx run cookiecutter <path-to-this-repo>

cd <your-tool>
git init && git add -A && git commit -m "Generate from ai-tool-starter"
make install && make dev      # http://localhost:3000, mock AI, sign-in off
```

The prompts ask for the tool's name, an Azure resource prefix, Entra ids
(placeholders are fine; real values go in GitHub settings later), and whether to
include **RAG** ("ask the documents" with Azure AI Search). Then follow the
generated project's `docs/runbook.md` to deploy.

## What every generated tool has

| Area | What you get |
| --- | --- |
| **Web** (`web/`) | Next.js 16 + React 19, Tailwind v4 with UNC brand tokens (WCAG 2.2 AA), app shell, UI primitives, MSAL v5 sign-in, streaming chat with Markdown, admin activity page, typed API client generated from OpenAPI, CSP and security headers |
| **API** (`api/`) | FastAPI with Entra JWT validation and app roles, AI provider layer (chat, SSE streaming, validated JSON output, embeddings; mock for local/tests), prompts as files, PostgreSQL + Alembic, audit trail of AI usage, structured logs with correlation ids, Application Insights tracing |
| **Topology** | Only the web app is public; it forwards `/api/*` to an internal API. One image per commit, configured at run time, promoted by digest |
| **CI/CD** | FO-AI script contract: `ci.sh` checks, Playwright e2e, `publish.sh` (build once in ACR + smoke test), `cd.sh` (validated config, Key Vault sync, health-gated rollout, automatic rollback), with ~70 tests for the deploy scripts |
| **Infra** | Bicep + one script per resource: identity, ACR, Key Vault, PostgreSQL Flexible Server, Storage, Log Analytics/App Insights, Container Apps; optional AI Search |
| **Optional RAG** | Blob indexer → chunking + embeddings in Azure AI Search → hybrid retrieval → grounded, cited, streamed answers |
| **Docs** | Architecture, local development, AI and the UNC Azure OpenAI hand-off, security, runbook (first deploy to operations), ADRs, `AGENTS.md` for coding agents |

## Repository layout

```
cookiecutter.json                 # prompts and defaults
hooks/                            # input validation; removes RAG files when opted out
scripts/verify-template.sh        # renders both variants and runs their checks
{{cookiecutter.project_slug}}/    # the generated project
  web/  api/  scripts/  deploy/  infra/  docs/  .github/
```

## Maintaining the template

See [TEMPLATE_USAGE.md](TEMPLATE_USAGE.md). In short: change files under
`{{cookiecutter.project_slug}}/`, then run `bash scripts/verify-template.sh` (add
`--docker` to build the images and run the smoke test). The template repo's CI runs
it for both variants on every pull request.
