/** MSAL (Microsoft Entra ID) browser configuration. */
import type { Configuration } from "@azure/msal-browser";

import { config } from "@/lib/config";

export const msalConfig: Configuration = {
  auth: {
    clientId: config.entra.clientId,
    authority: `https://login.microsoftonline.com/${config.entra.tenantId}`,
    redirectUri: config.entra.redirectUri,
    postLogoutRedirectUri: config.entra.redirectUri,
  },
  cache: {
    // sessionStorage keeps tokens per-tab and out of long-lived storage.
    cacheLocation: "sessionStorage",
    storeAuthStateInCookie: false,
  },
};

/** Scopes requested at login (OIDC basics). */
export const loginRequest = {
  scopes: ["openid", "profile", "email"],
};

/** Scope requested to call the backend API. */
export const apiRequest = {
  scopes: [config.entra.apiScope],
};
