/**
 * Backend API client.
 *
 * Calls are same-origin (`/api/...`): the Next.js server forwards them to the
 * FastAPI backend, so the browser never needs the API's address and there is no
 * CORS. `createApiClient` is a pure factory (no React, no MSAL) so it is easy to
 * test; `useApiClient` wires it to the signed-in user's token.
 *
 * Add one method per endpoint, typed with the generated schema in `./types`.
 */
import type { ChatRequest, ChatResponse, ErrorResponse, MeResponse } from "@/lib/api/types";

export class ApiError extends Error {
  readonly status: number;
  readonly code: string;
  readonly correlationId?: string | null;

  constructor(status: number, code: string, message: string, correlationId?: string | null) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.code = code;
    this.correlationId = correlationId;
  }
}

export type GetToken = () => Promise<string | null>;

export interface ApiClientOptions {
  getToken: GetToken;
  /** Defaults to same-origin. Only tests and server-side callers need to set it. */
  baseUrl?: string;
  fetchImpl?: typeof fetch;
}

export interface ApiClient {
  /** Low-level request with auth and error handling, for endpoints without a helper yet. */
  request<T>(path: string, init?: RequestInit): Promise<T>;
  /** Like `request`, but returns the raw Response (for streaming bodies). */
  raw(path: string, init?: RequestInit): Promise<Response>;
  getMe(): Promise<MeResponse>;
  chat(request: ChatRequest): Promise<ChatResponse>;
  /**
   * Server-sent events; read the body with `readServerSentEvents`. `path` selects the
   * streaming endpoint (plain chat by default; e.g. grounded answers when RAG is on).
   */
  chatStream(request: ChatRequest, signal?: AbortSignal, path?: string): Promise<Response>;
}

async function toApiError(response: Response): Promise<ApiError> {
  let code = "http_error";
  let message = `Request failed (${response.status})`;
  let correlationId = response.headers.get("X-Correlation-ID");
  try {
    const body = (await response.json()) as Partial<ErrorResponse>;
    if (body?.error) {
      code = body.error.code ?? code;
      message = body.error.message ?? message;
      correlationId = body.error.correlationId ?? correlationId;
    }
  } catch {
    // No JSON body; keep the defaults.
  }
  return new ApiError(response.status, code, message, correlationId);
}

export function createApiClient(options: ApiClientOptions): ApiClient {
  const doFetch = options.fetchImpl ?? fetch;
  const baseUrl = options.baseUrl ?? "";

  async function raw(path: string, init: RequestInit = {}): Promise<Response> {
    const token = await options.getToken();
    const headers = new Headers(init.headers);
    if (init.body && !headers.has("Content-Type")) {
      headers.set("Content-Type", "application/json");
    }
    if (token) headers.set("Authorization", `Bearer ${token}`);

    let response: Response;
    try {
      response = await doFetch(`${baseUrl}${path}`, { ...init, headers });
    } catch (cause) {
      if (cause instanceof DOMException && cause.name === "AbortError") throw cause;
      throw new ApiError(0, "network_error", "Could not reach the server.");
    }
    if (!response.ok) throw await toApiError(response);
    return response;
  }

  async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
    const response = await raw(path, init);
    return (await response.json()) as T;
  }

  return {
    request,
    raw,
    getMe: () => request<MeResponse>("/api/v1/me"),
    chat: (body: ChatRequest) =>
      request<ChatResponse>("/api/v1/chat", { method: "POST", body: JSON.stringify(body) }),
    chatStream: (body: ChatRequest, signal?: AbortSignal, path = "/api/v1/chat/stream") =>
      raw(path, {
        method: "POST",
        body: JSON.stringify(body),
        headers: { Accept: "text/event-stream" },
        signal,
      }),
  };
}
