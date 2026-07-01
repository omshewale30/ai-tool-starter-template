/**
 * Typed, centralized access to public runtime configuration.
 *
 * Only NEXT_PUBLIC_* variables are readable in the browser. Nothing secret
 * belongs here — privileged config lives in the backend.
 */

function required(name: string, value: string | undefined): string {
  // In auth-disabled local dev, Entra values may be intentionally blank.
  return value ?? "";
}

export const config = {
  apiBaseUrl: process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:8000",
  authDisabled: (process.env.NEXT_PUBLIC_AUTH_DISABLED ?? "false") === "true",
  entra: {
    clientId: required("NEXT_PUBLIC_ENTRA_CLIENT_ID", process.env.NEXT_PUBLIC_ENTRA_CLIENT_ID),
    tenantId: required("NEXT_PUBLIC_ENTRA_TENANT_ID", process.env.NEXT_PUBLIC_ENTRA_TENANT_ID),
    redirectUri:
      process.env.NEXT_PUBLIC_ENTRA_REDIRECT_URI ??
      (typeof window !== "undefined" ? window.location.origin : "http://localhost:3000"),
    apiScope: required("NEXT_PUBLIC_ENTRA_API_SCOPE", process.env.NEXT_PUBLIC_ENTRA_API_SCOPE),
  },
} as const;

export type AppConfig = typeof config;
