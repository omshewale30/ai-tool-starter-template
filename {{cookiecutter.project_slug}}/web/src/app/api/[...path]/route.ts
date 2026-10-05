/**
 * Forwards every `/api/*` request to the FastAPI backend (BACKEND_ORIGIN).
 *
 * The browser only ever talks to this web app, so there is no CORS and the API's
 * ingress can stay internal. This is a transparent forwarder, not an API surface:
 * it passes the caller's `Authorization` header through untouched (the API
 * validates the Entra token itself), bounds request bodies, and streams responses
 * back without buffering so server-sent events arrive as they are produced.
 */
import type { NextRequest } from "next/server";

import { MAX_FORWARD_BYTES, readBoundedBody } from "@/lib/api/bounded-body";
import { backendOrigin } from "@/lib/backend-origin";

// Hop-by-hop headers describe a single connection. Content-Encoding and
// Content-Length go with them because fetch decodes the body, so both would
// mislabel what is passed on.
const CONNECTION_HEADERS = new Set([
  "connection",
  "content-encoding",
  "content-length",
  "host",
  "keep-alive",
  "proxy-authenticate",
  "proxy-authorization",
  "te",
  "trailer",
  "transfer-encoding",
  "upgrade",
]);

function forwardableHeaders(headers: Headers): Headers {
  const forwardable = new Headers();
  headers.forEach((value, name) => {
    if (!CONNECTION_HEADERS.has(name)) forwardable.set(name, value);
  });
  return forwardable;
}

async function forwardToBackend(request: NextRequest): Promise<Response> {
  const { pathname, search } = request.nextUrl;
  const carriesBody = request.method !== "GET" && request.method !== "HEAD";

  // Reject a declared oversized body before reading; readBoundedBody bounds the rest.
  const declaredLength = request.headers.get("content-length");
  if (carriesBody && declaredLength) {
    if (!/^\d+$/.test(declaredLength) || Number(declaredLength) > MAX_FORWARD_BYTES) {
      return new Response(null, { status: 413 });
    }
  }
  const body = carriesBody ? await readBoundedBody(request.body) : undefined;
  if (body === null) return new Response(null, { status: 413 });

  let upstream: Response;
  try {
    upstream = await fetch(`${backendOrigin()}${pathname}${search}`, {
      method: request.method,
      headers: forwardableHeaders(request.headers),
      body,
      // The backend's own status is the answer, including any redirect.
      redirect: "manual",
      cache: "no-store",
      signal: request.signal,
    });
  } catch {
    return Response.json(
      { error: { code: "backend_unreachable", message: "The API is unreachable." } },
      { status: 502 },
    );
  }

  return new Response(upstream.body, {
    status: upstream.status,
    statusText: upstream.statusText,
    headers: forwardableHeaders(upstream.headers),
  });
}

// Every method, so an unsupported one gets FastAPI's 405 rather than one invented here.
export const GET = forwardToBackend;
export const HEAD = forwardToBackend;
export const POST = forwardToBackend;
export const PUT = forwardToBackend;
export const PATCH = forwardToBackend;
export const DELETE = forwardToBackend;
export const OPTIONS = forwardToBackend;
