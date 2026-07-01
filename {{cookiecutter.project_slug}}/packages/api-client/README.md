# @{{ cookiecutter.project_slug }}/api-client

Framework-agnostic, dependency-free TypeScript client and types for the
{{ cookiecutter.project_name }} backend. This is the canonical definition of the
backend contract (response shapes + the error envelope) plus a small
`createApiClient` factory that attaches an Entra access token to each request.

```ts
import { createApiClient } from "@{{ cookiecutter.project_slug }}/api-client";

const api = createApiClient({
  baseUrl: "https://api.example.com",
  getToken: async () => acquireAccessTokenSomehow(),
});

const me = await api.getMe();
const reply = await api.chat("Summarize this text...");
```

## Relationship to the web app

To keep the frontend runnable on its own, `apps/web` currently ships its own copy
of this client under `apps/web/src/lib/api`. In a larger setup, wire this package
as an npm/pnpm workspace dependency of `apps/web` and import from here instead —
then delete the copy so the contract lives in exactly one place.
