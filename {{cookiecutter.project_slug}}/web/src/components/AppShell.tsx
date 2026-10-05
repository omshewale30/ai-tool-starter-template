"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import type { ReactNode } from "react";

import { AuthGate } from "@/components/AuthGate";
import { Button } from "@/components/ui/Button";
import { Spinner } from "@/components/ui/Spinner";
import { useAuth } from "@/lib/auth/AuthProvider";
import { cn } from "@/lib/cn";
import { ORGANIZATION, SITE_NAME } from "@/lib/site";

/** Primary navigation. Add a page here when you add a route. */
const NAV_ITEMS = [
  { href: "/", label: "Home" },
  { href: "/chat", label: "Assistant" },
  { href: "/profile", label: "Profile" },
];

function NavLink({ href, label }: { href: string; label: string }) {
  const pathname = usePathname();
  const active = href === "/" ? pathname === "/" : pathname.startsWith(href);
  return (
    <Link
      href={href}
      aria-current={active ? "page" : undefined}
      className={cn(
        "rounded px-2 py-1 text-sm text-white no-underline hover:bg-unc-bolin hover:no-underline",
        "focus-visible:outline-white",
        active && "bg-unc-bolin font-semibold",
      )}
    >
      {label}
    </Link>
  );
}

/**
 * Header, navigation and footer, with every page gated behind sign-in.
 * The gate is UX only; the API rejects requests without a valid token.
 */
export function AppShell({ children }: { children: ReactNode }) {
  const { isReady, isAuthenticated, authDisabled, account, logout } = useAuth();

  let content: ReactNode = children;
  if (!isReady) content = <Spinner label="Checking your sign-in…" />;
  else if (!isAuthenticated) content = <AuthGate />;

  return (
    <div className="flex min-h-screen flex-col">
      {authDisabled ? (
        <div role="note" className="bg-warning-bg px-4 py-2 text-center text-sm text-warning">
          Sign-in is disabled for local development. Never deploy this configuration.
        </div>
      ) : null}

      <header className="border-t-4 border-unc-blue bg-unc-navy text-white">
        <div className="mx-auto flex max-w-5xl flex-wrap items-center justify-between gap-3 px-4 py-3">
          <Link
            href="/"
            className="text-lg font-bold text-white no-underline hover:no-underline focus-visible:outline-white"
          >
            {SITE_NAME}
          </Link>
          {isAuthenticated ? (
            <nav aria-label="Primary" className="flex flex-wrap items-center gap-1">
              {NAV_ITEMS.map((item) => (
                <NavLink key={item.href} {...item} />
              ))}
            </nav>
          ) : null}
          {isAuthenticated && account ? (
            <div className="flex items-center gap-3 text-sm">
              <span className="text-unc-cloud">{account.name}</span>
              {authDisabled ? null : (
                <Button
                  variant="ghost"
                  className="min-h-8 px-2 text-white hover:bg-unc-bolin focus-visible:outline-white"
                  onClick={logout}
                >
                  Sign out
                </Button>
              )}
            </div>
          ) : null}
        </div>
      </header>

      <main id="main-content" tabIndex={-1} className="mx-auto w-full max-w-5xl flex-1 px-4 py-8">
        {content}
      </main>

      <footer className="border-t border-border bg-surface">
        <div className="mx-auto max-w-5xl px-4 py-4 text-sm text-muted">
          {ORGANIZATION} · The University of North Carolina at Chapel Hill
        </div>
      </footer>
    </div>
  );
}
