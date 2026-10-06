# ADR 0001: Standard stack

- Status: Accepted
- Date: 2024-01-01

## Context

Internal teams need to ship AI-native web tools quickly and consistently on
Azure. Divergent stacks slow onboarding, reviews, and platform support. We want a
small, boring, well-supported set of technologies that most engineers already
know or can learn fast.

## Decision

Standardize on:

- **Next.js + TypeScript** frontend — ubiquitous React framework, App Router,
  strong typing, first-class Vercel/Node tooling and static/SSR options.
- **FastAPI + Python** backend — fast to write, typed via Pydantic, excellent for
  AI/data workloads where the Python ecosystem lives, automatic OpenAPI.
- **Microsoft Entra ID** for auth — UNC's identity provider (Onyen sign-in); SSO,
  conditional access, and app roles come for free.
- **UNC's Azure OpenAI / AI Foundry** for AI — the sanctioned model access, with
  governance and quotas owned by UNC, reachable with managed identity.
- **Tailwind CSS** with UNC brand tokens for styling, held to WCAG 2.2 AA.

Supporting choices: PostgreSQL Flexible Server, Blob Storage, optional AI Search,
Key Vault, Container Apps, Application Insights, Bicep, and GitHub Actions through
the shared FO-AI/automation workflows ([0006](0006-fo-ai-script-contract.md)).

Updated 2026-10: Azure SQL replaced by PostgreSQL (lighter local development, Entra
or password auth, pgvector available); CI/CD moved to the FO-AI script contract.

## Consequences

- New projects start from one template with the seams already wired.
- Reviewers and the platform team share a common mental model.
- Python on the backend keeps AI/data code idiomatic; TypeScript on the frontend
  keeps the UI ecosystem idiomatic — at the cost of two languages in one repo.
- We are intentionally coupled to Azure + Entra. Portability is not a goal for
  internal tools; leveraging managed services and SSO is.
