"use client";

/**
 * App-wide authentication boundary.
 *
 * Exposes a small, MSAL-agnostic `useAuth()` context so components never touch
 * MSAL directly. All MSAL hooks live in `EntraAuthBridge`, which is only mounted
 * when auth is enabled, so local development needs no Entra configuration.
 *
 * Authorization is always enforced by the API; anything here is UX only.
 */
import {
  AuthError,
  CacheLookupPolicy,
  InteractionRequiredAuthError,
  InteractionStatus,
  type AccountInfo,
} from "@azure/msal-browser";
import { MsalProvider, useIsAuthenticated, useMsal } from "@azure/msal-react";
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  type ReactNode,
} from "react";

import type { EntraConfig } from "@/lib/auth/entra-config";
import { apiRequest, getMsalInstance, loginRequest } from "@/lib/auth/msalConfig";

/*
 * Build-time on purpose, and the one auth value that is NOT read at runtime:
 * `next build` inlines it, so a published image (built without it) can never have
 * sign-in switched off by an environment variable. Pairs with the API's
 * AUTH_MODE=disabled for local development and the Playwright build.
 */
const AUTH_DISABLED = process.env.NEXT_PUBLIC_AUTH_DISABLED === "true";

export interface AuthAccount {
  name: string;
  email: string;
}

export interface AuthContextValue {
  /** False until MSAL has restored any existing session. Wait for it before gating. */
  isReady: boolean;
  isAuthenticated: boolean;
  authDisabled: boolean;
  account: AuthAccount | null;
  login: (redirectTo?: string) => void;
  logout: () => void;
  /** An access token for the API, or null. May redirect to Entra when interaction is required. */
  getToken: () => Promise<string | null>;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used within <AuthProvider>");
  return ctx;
}

/** Server render / pre-hydration: nothing known yet. */
const PENDING_VALUE: AuthContextValue = {
  isReady: false,
  isAuthenticated: false,
  authDisabled: false,
  account: null,
  login: () => {},
  logout: () => {},
  getToken: async () => null,
};

/** Local development: a clearly fake principal. The API ignores tokens when AUTH_MODE=disabled. */
const DISABLED_VALUE: AuthContextValue = {
  isReady: true,
  isAuthenticated: true,
  authDisabled: true,
  account: { name: "Local Developer", email: "dev@localhost" },
  login: () => {},
  logout: () => {},
  getToken: async () => null,
};

/** Errors only a redirect to Entra can fix (token renewal never uses MSAL's hidden iframe). */
function needsRedirect(error: unknown): boolean {
  return (
    error instanceof InteractionRequiredAuthError ||
    (error instanceof AuthError && error.errorCode === "invalid_grant")
  );
}

function EntraAuthBridge({ apiScope, children }: { apiScope: string; children: ReactNode }) {
  const { instance, accounts, inProgress } = useMsal();
  const isAuthenticated = useIsAuthenticated();
  // msal-browser v5 cannot read its cache until initialize() has run, which
  // MsalProvider does in an effect; nothing is signed in during Startup.
  const starting = inProgress === InteractionStatus.Startup;
  const active = useMemo<AccountInfo | null>(
    () => (starting ? null : (instance.getActiveAccount() ?? accounts[0] ?? null)),
    [starting, instance, accounts],
  );
  const redirectStarted = useRef(false);

  useEffect(() => {
    if (!starting && !instance.getActiveAccount() && accounts[0]) {
      instance.setActiveAccount(accounts[0]);
    }
  }, [starting, instance, accounts]);

  const login = useCallback(
    (redirectTo?: string) => {
      if (inProgress !== InteractionStatus.None) return;
      const redirectStartPage = redirectTo
        ? new URL(redirectTo, window.location.origin).href
        : undefined;
      instance.loginRedirect({ ...loginRequest, redirectStartPage }).catch((error: unknown) => {
        console.error("Sign-in redirect failed", error);
      });
    },
    [instance, inProgress],
  );

  const logout = useCallback(() => {
    if (inProgress !== InteractionStatus.None) return;
    void instance.logoutRedirect({ account: instance.getActiveAccount() ?? undefined });
  }, [instance, inProgress]);

  const tokenRequest = useMemo(() => apiRequest(apiScope), [apiScope]);

  const getToken = useCallback(async () => {
    if (!active || inProgress !== InteractionStatus.None) return null;
    try {
      const result = await instance.acquireTokenSilent({
        ...tokenRequest,
        account: active,
        // Cached token, then refresh token; never the hidden iframe, which needs
        // third-party cookies and a frameable redirect page.
        cacheLookupPolicy: CacheLookupPolicy.AccessTokenAndRefreshToken,
      });
      return result.accessToken;
    } catch (error) {
      if (!needsRedirect(error)) throw error;
      if (redirectStarted.current) return null;
      redirectStarted.current = true;
      try {
        await instance.acquireTokenRedirect({ ...tokenRequest, account: active });
      } catch (redirectError) {
        redirectStarted.current = false;
        throw redirectError;
      }
      return null;
    }
  }, [active, inProgress, instance, tokenRequest]);

  const value = useMemo<AuthContextValue>(
    () => ({
      isReady: inProgress === InteractionStatus.None,
      isAuthenticated,
      authDisabled: false,
      account: active ? { name: active.name ?? active.username, email: active.username } : null,
      login,
      logout,
      getToken,
    }),
    [active, getToken, inProgress, isAuthenticated, login, logout],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function AuthProvider({ entra, children }: { entra: EntraConfig; children: ReactNode }) {
  // `entra` cannot change within a document and the instance is a singleton.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const instance = useMemo(() => (AUTH_DISABLED ? null : getMsalInstance(entra)), []);

  if (AUTH_DISABLED) {
    return <AuthContext.Provider value={DISABLED_VALUE}>{children}</AuthContext.Provider>;
  }

  if (!entra.clientId || !entra.tenantId || !entra.apiScope) {
    // Fail loudly rather than render a sign-in button that cannot work.
    throw new Error(
      "Entra is not configured. Set ENTRA_CLIENT_ID, ENTRA_TENANT_ID and ENTRA_API_SCOPE on " +
        "the web app (no NEXT_PUBLIC_ prefix; they are read per request).",
    );
  }

  if (!instance) {
    return <AuthContext.Provider value={PENDING_VALUE}>{children}</AuthContext.Provider>;
  }

  return (
    <MsalProvider instance={instance}>
      <EntraAuthBridge apiScope={entra.apiScope}>{children}</EntraAuthBridge>
    </MsalProvider>
  );
}
