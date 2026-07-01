# ADR 0002: Backend-only AI access

- Status: Accepted
- Date: 2024-01-01

## Context

The frontend runs in the user's browser, where any secret, endpoint, or token it
holds is fully exposed. Azure AI Foundry access is privileged: it carries cost,
quota, data-governance, and prompt-safety concerns. It is tempting to call the AI
service directly from the SPA to save a hop.

## Decision

The frontend must **never** call Azure AI Foundry (or any privileged Azure
service) directly. All AI calls go through the FastAPI backend via the
`AIProvider` abstraction. The browser only ever talks to our own API with a
user-scoped Entra token.

## Consequences

- **Credentials stay server-side.** AI access uses the backend's managed
  identity; no keys or model endpoints reach the browser.
- **A single control point.** Authorization, rate limiting, input/output
  validation, auditing, and prompt hardening live in one place
  (`services/ai/`).
- **Swappable providers.** Mock vs. Foundry is a backend config switch
  (`AI_PROVIDER`); the frontend is unaffected. Local dev and tests need no Azure.
- **Cost/latency.** One extra network hop, accepted for the security and control
  benefits. Streaming responses can be added at the backend edge if needed.
- The same rule applies to Storage, Search, and the database: privileged access
  is backend-only.
