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
- **Microsoft Entra ID** for auth — the organization's identity provider; SSO,
  conditional access, app roles/groups come for free.
- **Azure AI Foundry** for AI — the sanctioned platform for model access,
  governance, and quotas, reachable with managed identity.

Supporting choices: Azure SQL, Blob Storage, optional AI Search, Key Vault,
Container Apps, App Insights, GitHub Actions, and Bicep.

## Consequences

- New projects start from one template with the seams already wired.
- Reviewers and the platform team share a common mental model.
- Python on the backend keeps AI/data code idiomatic; TypeScript on the frontend
  keeps the UI ecosystem idiomatic — at the cost of two languages in one repo.
- We are intentionally coupled to Azure + Entra. Portability is not a goal for
  internal tools; leveraging managed services and SSO is.
