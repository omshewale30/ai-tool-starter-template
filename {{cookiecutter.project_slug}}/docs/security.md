# Security

## Identity model (Microsoft Entra ID)

Two app registrations:

- **Frontend (SPA)** — public client. Users sign in here via MSAL. It requests
  delegated access to the backend API scope.
- **Backend (Web/API)** — exposes an API scope (e.g. `access_as_user`) and,
  optionally, **app roles** (e.g. `admin`). Access tokens issued for this API
  carry the caller's identity and role/group claims.

The frontend never sees any client secret. It uses the authorization-code flow
with PKCE (handled by MSAL).

## Token validation

The backend validates every access token (`core/security.py`):

- **Signature** — verified against the tenant's published JWKS
  (`https://login.microsoftonline.com/<tenant>/discovery/v2.0/keys`).
- **Issuer** — must equal `https://login.microsoftonline.com/<tenant>/v2.0`.
- **Audience** — must equal the backend app id URI or client id.
- **Expiry** — enforced (with a small configurable leeway).

Validation failures return `401` with the standard error envelope. Keys are
cached in-process by `PyJWKClient`.

## Authorization

- `get_current_user` resolves the caller into a `Principal` (subject, name,
  email, roles, groups).
- `require_admin` gates admin routes: it allows the `admin` app role **or**
  membership in the configured `ADMIN_GROUP_ID`.
- Authorization is always enforced server-side. The UI only uses claims for
  presentation (e.g. hiding links) — never as a security boundary.

## The `AUTH_MODE=disabled` bypass

For local development only, `AUTH_MODE=disabled` skips token validation and
injects a clearly-fake development principal (`is_dev_principal=True`). It is
deliberately loud:

- The backend logs a warning on startup and on every token resolution.
- `/api/v1/me` returns `isDevPrincipal: true`.
- The frontend shows a persistent "Auth is disabled" banner.
- The backend refuses to start if `AUTH_MODE=disabled` and `ENVIRONMENT` is not
  `local` or `test`.

Never set `AUTH_MODE=disabled` in a deployed environment. Deployments default to
`AUTH_MODE=entra` (see the Bicep parameters).

## Secrets management

- **No secrets in source or images.** `.env`/`.env.local` are git-ignored;
  only `*.example` files are committed.
- In Azure, secrets live in **Key Vault** and are surfaced to Container Apps as
  **Key Vault references** resolved by the app's **managed identity**.
- The SQL admin password and image tags are passed to Bicep via environment
  variables in CI (`readEnvironmentVariable`), not committed.

## Managed identity / keyless auth

A single **user-assigned managed identity** is granted least-privilege roles:

| Resource | Role |
| --- | --- |
| ACR | AcrPull |
| Key Vault | Key Vault Secrets User |
| Storage | Storage Blob Data Contributor |
| AI Search (optional) | Search Index Data Reader |
| Azure SQL | Entra admin / DB user |

Backend Azure SDK calls use `DefaultAzureCredential`, which selects this identity
in Azure (`AZURE_CLIENT_ID` is set) and falls back to `az login` locally.

## AI service access

Azure AI Foundry is called **only** from the backend service layer
(`services/ai/foundry_provider.py`) using managed identity — never from the
browser. This keeps model access, quotas, and prompt/response handling on a
trusted tier. See [`adr/0002-backend-only-ai-access.md`](adr/0002-backend-only-ai-access.md).

## Logging cautions

- Logs are structured JSON with a correlation id. **Do not log** access tokens,
  full prompts/responses that may contain sensitive data, secrets, or PII.
- The audit trail records *that* an event happened (e.g. `chat.completed`) and by
  whom — not message content.
- Unhandled exceptions are logged server-side with detail but return a generic
  message to clients (no internal leakage).

## Transport & CORS

- All ingress is HTTPS (Container Apps; `allowInsecure: false`).
- CORS on the backend is restricted to the configured frontend origin(s)
  (`CORS_ALLOW_ORIGINS`).
