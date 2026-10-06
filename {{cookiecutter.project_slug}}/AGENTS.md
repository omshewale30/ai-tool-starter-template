# Working in this repository

{{ cookiecutter.project_name }}: a Next.js web app (`web/`) in front of a FastAPI API
(`api/`) for UNC-Chapel Hill Finance and Operations. Read
[docs/architecture.md](docs/architecture.md) first.

## Commands

| | |
| --- | --- |
| Set up | `make install` |
| Run locally | `make dev` (Postgres in docker, API :8000, web :3000, mock AI, sign-in off) |
| Everything CI checks | `make check` (`scripts/ci.sh backend` and `frontend`) |
| End-to-end | `make e2e` |
| After changing API routes/schemas | `make generate-api`, commit `web/src/lib/api/schema.ts` |
| After changing models | `make migration m="..."`, review, `make migrate` |

`web/` is **Next.js 16**: read `web/AGENTS.md` and the docs in
`web/node_modules/next/dist/docs/` before writing Next.js code.

## Rules

- **The browser never calls models or Azure services.** AI goes through
  `app/services/ai` (`AI` dependency), data through the API.
- **Authorization lives in the API.** Use `CurrentUser` / `AdminUser`; UI checks are
  cosmetic.
- **No environment-specific values at build time.** Never add `NEXT_PUBLIC_*`
  variables or Docker build args; read config at run time (`web/src/lib/auth/entra-config.ts`,
  `web/src/lib/backend-origin.ts`). The only exception is `NEXT_PUBLIC_AUTH_DISABLED`.
- **Every deployable setting has one owner** in `deploy/env-contract.json`. Adding a
  field to `api/app/core/config.py` or a `process.env.X` read in `web/src` without
  updating the contract fails `scripts/tests/test_env_contract.py`.
- **Generated types are committed** and must be current (CI regenerates and diffs).
- **The FO-AI script contract** ([ADR 0006](docs/adr/0006-fo-ai-script-contract.md)):
  `scripts/ci.sh` never touches the cloud; `publish.sh` never deploys; `cd.sh` never
  builds. The deploy scripts have tests in `scripts/tests/`; keep them passing and add
  a test for each new failure mode.
- **Infra creates, CD owns.** Don't change container app env or images in Bicep for
  running apps; change the contract and redeploy.
- **Never log** tokens, secrets, prompts, answers, or personal data. Audit events
  record usage, not content.
- **UI:** use the primitives in `web/src/components/ui/` and the tokens in
  `web/src/app/globals.css`. WCAG 2.2 AA: Carolina Blue `#4B9CD3` is for surfaces
  and borders, not text on white; white text only on Bolin Creek `#2C5080` or Navy
  `#13294B`; links `#007FAE`; visible focus outlines; announce finished answers, not
  every streamed token.
- **Prompts** live in `api/app/prompts/*.md`, not in route code.
- Keep changes small and focused; match the surrounding code's style and comments.
