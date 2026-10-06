# ADR 0004: The web app forwards /api/*; the API is internal

- Status: Accepted
- Date: 2026-10-05

## Context

The browser must call the API with the user's Entra token. Two shapes are common
in FO-AI apps: the browser calls a public API directly (CORS, two public endpoints),
or the web app forwards same-origin requests to a private API.

## Decision

The browser calls only its own origin. `web/src/app/api/[...path]/route.ts`
forwards `/api/*` to `BACKEND_ORIGIN` (the API's internal FQDN), passing headers,
including `Authorization`, through unchanged and streaming responses back. The API
container app has internal ingress only.

A route handler, not `next.config` rewrites: rewrites are fixed at `next build`, which
would bake the backend address into the image ([0005](0005-publish-once-runtime-config.md)).

## Consequences

- One public endpoint; the API's attack surface is the forwarder's, and no CORS
  configuration exists to get wrong.
- The API still validates every token; the forwarder makes no auth decisions.
- Server-sent events must not be buffered; the forwarder streams `response.body`
  and the API sets `Cache-Control: no-transform`.
- The deploy verifies the whole chain with one request, `<web>/api/health`, and
  derives `BACKEND_ORIGIN` from the API app's actual ingress FQDN.
- An extra hop per API call (in-environment, small).
