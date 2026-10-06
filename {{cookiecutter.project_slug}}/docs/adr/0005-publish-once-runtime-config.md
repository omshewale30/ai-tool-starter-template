# ADR 0005: Publish once, configure at run time, promote by digest

- Status: Accepted
- Date: 2026-10-05

## Context

Next.js inlines `NEXT_PUBLIC_*` variables at build time, so a web image built that
way is tied to one environment, and what is tested is not what ships elsewhere.
Rebuilding during deploy has the same problem.

## Decision

- Each commit on `main` is built **once** (`scripts/publish.sh`), tagged with the
  commit SHA, smoke-tested as the pushed digests (`scripts/smoke.sh`), and deployed
  **by digest** (`scripts/cd.sh`). Deploys never build.
- Images take **no build arguments**. The web reads `BACKEND_ORIGIN` and `ENTRA_*`
  per request; the root layout is dynamic and passes them to the client.
- The single exception is `NEXT_PUBLIC_AUTH_DISABLED`, deliberately build-time so a
  published image cannot have sign-in disabled by configuration.
- Every deployable setting has exactly one owner in `deploy/env-contract.json`;
  tests keep it equal to what the API's `Settings` and the web read.

## Consequences

- The digest that passed the smoke test is the one running; promotion to another
  environment is a deploy, not a build.
- Configuration changes are a redeploy (env update), not a rebuild.
- The smoke test asserts the runtime client id appears on the page, which fails if
  configuration is ever baked in again.
