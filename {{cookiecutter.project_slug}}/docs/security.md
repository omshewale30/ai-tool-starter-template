# Security

## Exposure

Only the **web** container app has public ingress. It serves the UI and forwards
`/api/*` to the **API**, whose ingress is internal to the Container Apps environment
(`cd.sh` refuses to deploy if it isn't). The forwarder passes requests through
unchanged, including the `Authorization` header; it makes no authorization
decisions. There is no CORS: the browser only calls its own origin.

## Identity (Microsoft Entra ID)

Two app registrations ([runbook](runbook.md#1-app-registrations)):

- **Web (SPA)**: public client; users sign in with MSAL using the authorization code
  flow with PKCE, redirect URI `<origin>/auth`. No client secret exists.
- **API**: exposes the delegated scope `access_as_user` and the `admin` app role, and
  issues **v2** access tokens.

Tokens are cached by MSAL v5 in encrypted `localStorage`; silent renewal uses the
refresh token, never a hidden iframe.

## Token validation (`api/app/core/security.py`)

Every API request (except health) validates the bearer token:

- **signature** against the tenant JWKS (keys cached by `PyJWKClient`);
- **issuer** `https://login.microsoftonline.com/<tenant>/v2.0`;
- **audience** the API's app id URI or client id;
- **expiry**, with a small leeway (`JWT_LEEWAY_SECONDS`).

Failures return `401` with the standard error envelope.

## Authorization

- `CurrentUser` resolves the caller to a `Principal` (object id, name, email, roles).
- `AdminUser` requires the `admin` **app role** (or membership in `ADMIN_GROUP_ID`).
  Prefer app roles: Entra omits the `groups` claim for users in more than 200 groups.
- Authorization is enforced only in the API. The UI hides links for convenience.

## Local development bypass

`AUTH_MODE=disabled` (API) and `NEXT_PUBLIC_AUTH_DISABLED=true` (web build) replace
sign-in with a clearly fake admin principal for local development and tests. Guards:

- the API refuses to start with `AUTH_MODE=disabled` unless `ENVIRONMENT` is `local`
  or `test`, and logs a warning;
- the web flag is **build-time**: published images are built without it, so no
  environment variable can switch sign-in off in Azure;
- the deploy contract requires `AUTH_MODE=entra`, and the deploy's health check
  requires `auth.mode == "entra"` and `auth.configured`;
- the UI shows a permanent warning banner.

## Secrets

- Nothing secret is committed or baked into an image. `.env` files are git-ignored;
  only `*.example` files are committed.
- In Azure, secrets are **Key Vault references** resolved by the app's managed
  identity. `database-url` is owned by CD (from the `DATABASE_URL` GitHub secret);
  `appinsights-connection-string` is seeded by infra.
- `scripts/cd.sh` never puts a secret on a command line or in a log: the secrets
  object goes only to the renderer, values are written to `0600` files and passed with
  `--file`, extracted values are masked, and every mutating `az` call uses `-o none`.
  `scripts/tests/test_deploy.py` enforces this.
- CI/CD authenticates with OIDC federated credentials; there are no Azure passwords
  in GitHub.

## Managed identity (keyless Azure access)

One user-assigned identity is used by both apps:

| Resource | Role |
| --- | --- |
| Container Registry | AcrPull |
| Key Vault | Key Vault Secrets User |
| Storage | Storage Blob Data Contributor |
| UNC Azure OpenAI | Cognitive Services OpenAI User (granted by UNC) |
{%- if cookiecutter.enable_ai_search == "yes" %}
| AI Search | Search Index Data Reader |
{%- endif %}

The API's Azure SDK calls use `DefaultAzureCredential` (`AZURE_CLIENT_ID` selects
this identity). PostgreSQL uses a password held in Key Vault; switch to Entra
authentication for the database if your data warrants it.

## AI

- Models are called only by the API ([ADR 0002](adr/0002-backend-only-ai-access.md)),
  with the managed identity; no keys or endpoints reach the browser.
- Model output is rendered with `react-markdown`, which never renders raw HTML.
- The audit trail and telemetry record usage (model, tokens, latency), **not** prompts
  or answers. Do not add prompt logging without a data-handling decision.
- Prompts (`api/app/prompts/`) tell the model not to request or repeat sensitive
  personal data; that is guidance, not a control. Don't send data the model isn't
  approved for.

## Browser hardening

`web/src/proxy.ts` sets, on every page: a nonce-based **Content-Security-Policy**
(scripts only from this origin with the per-request nonce; network calls only to this
origin and Entra; no framing), `X-Content-Type-Options`, `X-Frame-Options: DENY`,
`Referrer-Policy`, `Permissions-Policy`, and HSTS. Request bodies forwarded to the API
are capped (`web/src/lib/api/bounded-body.ts`).

## Logging

- Structured JSON with a correlation id; the id from a caller is accepted only if it
  is short and plain, so it can't forge log lines.
- Never log tokens, secrets, prompts/answers, or other personal data.
- Unhandled errors are logged with detail but return a generic message and the
  correlation id to the client.

## Not included (add when a tool needs it)

Rate limiting / per-user quotas, private networking (VNet, private endpoints), and
Entra authentication for PostgreSQL. See [ai.md](ai.md) for where quotas would go.
