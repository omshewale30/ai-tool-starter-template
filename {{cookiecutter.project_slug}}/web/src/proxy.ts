/**
 * Per-request security headers, including a nonce-based Content-Security-Policy.
 *
 * Next.js reads the nonce from the CSP request header and applies it to its own
 * scripts, so pages must render dynamically (the root layout opts in). `/api/*`
 * is excluded: those responses come from the FastAPI backend.
 */
import { NextResponse, type NextRequest } from "next/server";

function contentSecurityPolicy(nonce: string): string {
  // React needs eval in development only, for richer error stacks.
  const devEval = process.env.NODE_ENV === "development" ? " 'unsafe-eval'" : "";
  return [
    "default-src 'self'",
    `script-src 'self' 'nonce-${nonce}' 'strict-dynamic'${devEval}`,
    "style-src 'self' 'unsafe-inline'",
    // MSAL talks to Entra from the browser; everything else is same-origin.
    "connect-src 'self' https://login.microsoftonline.com",
    "img-src 'self' data: blob:",
    "font-src 'self'",
    "frame-src https://login.microsoftonline.com",
    "object-src 'none'",
    "frame-ancestors 'none'",
    "base-uri 'self'",
    "form-action 'self'",
  ].join("; ");
}

export function proxy(request: NextRequest) {
  const nonce = btoa(crypto.randomUUID());
  const policy = contentSecurityPolicy(nonce);

  const requestHeaders = new Headers(request.headers);
  requestHeaders.set("x-nonce", nonce);
  requestHeaders.set("Content-Security-Policy", policy);

  const response = NextResponse.next({ request: { headers: requestHeaders } });
  response.headers.set("Content-Security-Policy", policy);
  response.headers.set("X-Content-Type-Options", "nosniff");
  response.headers.set("X-Frame-Options", "DENY");
  response.headers.set("Referrer-Policy", "strict-origin-when-cross-origin");
  response.headers.set("Permissions-Policy", "camera=(), microphone=(), geolocation=()");
  response.headers.set("Strict-Transport-Security", "max-age=31536000; includeSubDomains");
  return response;
}

export const config = {
  matcher: [
    {
      source: "/((?!api|_next/static|_next/image|favicon.ico).*)",
      // Prefetches don't render HTML that needs a nonce.
      missing: [
        { type: "header", key: "next-router-prefetch" },
        { type: "header", key: "purpose", value: "prefetch" },
      ],
    },
  ],
};
