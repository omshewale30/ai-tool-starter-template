import type { Metadata } from "next";
import type { ReactNode } from "react";

import { AppShell } from "@/components/AppShell";
import { AuthProvider } from "@/lib/auth/AuthProvider";
import { entraConfig } from "@/lib/auth/entra-config";
import { SITE_DESCRIPTION, SITE_NAME } from "@/lib/site";
import "./globals.css";

export const metadata: Metadata = {
  title: { default: SITE_NAME, template: `%s · ${SITE_NAME}` },
  description: SITE_DESCRIPTION,
};

/*
 * Never prerendered: the Entra identifiers are read from the environment on every
 * request so the image stays environment-agnostic (a static layout would bake the
 * empty build-time values in), and the CSP nonce in src/proxy.ts is per request.
 */
export const dynamic = "force-dynamic";

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body>
        <a
          href="#main-content"
          className="sr-only rounded bg-surface px-3 py-2 focus:not-sr-only focus:absolute focus:left-2 focus:top-2 focus:z-50"
        >
          Skip to main content
        </a>
        <AuthProvider entra={entraConfig()}>
          <AppShell>{children}</AppShell>
        </AuthProvider>
      </body>
    </html>
  );
}
