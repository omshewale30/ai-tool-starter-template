/** MSAL (Microsoft Entra ID) browser configuration. */
import {
  BrowserCacheLocation,
  PublicClientApplication,
  type Configuration,
} from "@azure/msal-browser";

import type { EntraConfig } from "@/lib/auth/entra-config";

/** This app's sign-in landing route (`src/app/auth/page.tsx`). */
export const AUTH_REDIRECT_PATH = "/auth";

/**
 * Browser-only: the redirect URI is derived from the page's own origin, which
 * removes the commonest cause of AADSTS50011 (a configured redirect URI that
 * disagrees with the origin the user is on). Register `<origin>/auth` for every
 * environment as a **SPA** redirect URI on the web app registration.
 */
export function buildMsalConfig(entra: EntraConfig): Configuration {
  const redirectUri = `${window.location.origin}${AUTH_REDIRECT_PATH}`;
  return {
    auth: {
      clientId: entra.clientId,
      authority: `https://login.microsoftonline.com/${entra.tenantId}`,
      redirectUri,
      postLogoutRedirectUri: redirectUri,
    },
    cache: {
      // msal-browser v5 encrypts this cache; it outlives the tab only when Entra
      // reports keep-me-signed-in. Access tokens are short-lived.
      cacheLocation: BrowserCacheLocation.LocalStorage,
    },
  };
}

/** Scopes requested at sign-in (OIDC basics; no Microsoft Graph consent needed). */
export const loginRequest = {
  scopes: ["openid", "profile", "email"],
};

/** The delegated scope for the backend API: `api://<api client id>/access_as_user`. */
export function apiRequest(apiScope: string): { scopes: string[] } {
  return { scopes: [apiScope] };
}

let browserInstance: PublicClientApplication | null = null;

/**
 * Lazily created MSAL singleton, one per tab, created outside React so StrictMode
 * double renders and fast refresh can't produce a second cache-owning client.
 * Returns null during server rendering, where there is no browser storage.
 */
export function getMsalInstance(entra: EntraConfig): PublicClientApplication | null {
  if (typeof window === "undefined") return null;
  browserInstance ??= new PublicClientApplication(buildMsalConfig(entra));
  return browserInstance;
}
