# ADR 0006: The FO-AI repository script contract

- Status: Accepted
- Date: 2026-10-05

## Context

FO-AI apps share reusable CI and Azure CD workflows (`FO-AI/automation`). Each app
supplies its own build, check and deploy logic; a consistent shape lets anyone move
between repos.

## Decision

Follow the contract documented in the FO-AI/automation README:

| Script | Does | Never |
| --- | --- | --- |
| `scripts/ci.sh <check>` | one named check (`backend`, `frontend`); sets its own test env | touches the cloud or reads secrets |
| `scripts/publish.sh` | builds `<repo>-api`/`<repo>-web` at the commit SHA in ACR, smoke-tests the pushed digests | deploys, tags `latest` |
| `scripts/cd.sh` | resolves digests, validates config, rechecks `main`, rolls out API then web, verifies, rolls back | builds, accepts a digest from its environment |

`.github/workflows/ci.yml` (checks, e2e, single `verify` gate, `publish` on main) and
`cd.yml` (calls `reusable-azure-cd.yml` for `dev`) pin the reusable workflows by full
commit SHA; bump both together.

## Consequences

- Infrastructure is created by hand once (`infra/scripts`); CI/CD never provisions.
- The deploy scripts are product code with tests (`scripts/tests/`, run by
  `ci.sh backend`) against fake `az`/`gh`/`curl`.
- Changes to the shared workflows reach this repo only when the pin is bumped.
