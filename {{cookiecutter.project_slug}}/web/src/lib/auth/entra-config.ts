/**
 * The browser-facing Entra identifiers, read from the environment per request.
 *
 * No `NEXT_PUBLIC_` prefix, by design: `next build` inlines `NEXT_PUBLIC_*` into the
 * bundle, which would tie the image to one environment. The root layout reads these
 * on every request and hands them to `AuthProvider` as a prop, so one image digest
 * is promoted across environments. They are public identifiers, not secrets.
 *
 * Nothing may capture this at module scope.
 */
export interface EntraConfig {
  clientId: string;
  tenantId: string;
  apiScope: string;
}

export function entraConfig(): EntraConfig {
  return {
    clientId: process.env.ENTRA_CLIENT_ID?.trim() ?? "",
    tenantId: process.env.ENTRA_TENANT_ID?.trim() ?? "",
    apiScope: process.env.ENTRA_API_SCOPE?.trim() ?? "",
  };
}
