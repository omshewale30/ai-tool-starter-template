"use client";

import type { ReactNode } from "react";

import { NavBar } from "@/components/NavBar";
import { useAuth } from "@/lib/auth/AuthProvider";

/**
 * The authenticated application shell.
 *
 * Renders the nav and, when auth is enabled, gates protected content behind a
 * sign-in prompt (the "unauthorized" state). Authorization decisions are always
 * enforced by the backend as well — this is UX, not a security boundary.
 */
export function AuthShell({ children }: { children: ReactNode }) {
  const { isAuthenticated, authDisabled, login } = useAuth();

  return (
    <div className="app-shell">
      {authDisabled ? (
        <div className="banner banner-warning">
          Auth is disabled (local development mode). Do not use this configuration in a deployed
          environment.
        </div>
      ) : null}
      <NavBar />
      <main className="main">
        {isAuthenticated ? (
          children
        ) : (
          <div className="card">
            <h2>Sign in required</h2>
            <p className="muted">Please sign in with your organization account to continue.</p>
            <button className="btn" type="button" onClick={login}>
              Sign in with Microsoft
            </button>
          </div>
        )}
      </main>
    </div>
  );
}
