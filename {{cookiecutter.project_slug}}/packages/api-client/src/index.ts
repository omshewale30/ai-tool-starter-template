/**
 * Framework-agnostic client and response types for the backend API.
 *
 * This package is the canonical, dependency-free definition of the backend
 * contract. The Next.js app currently ships its own copy under
 * `apps/web/src/lib/api` so it can run standalone; in a larger monorepo you can
 * make `apps/web` depend on this package (npm/pnpm workspace) and delete the
 * copy. Keeping the shapes here documents the contract in one place.
 */

export interface MeResponse {
  subject: string;
  name: string;
  email: string;
  roles: string[];
  groups: string[];
  isAdmin: boolean;
  isDevPrincipal: boolean;
}

export interface ChatResponse {
  response: string;
  model?: string | null;
}

export interface ApiErrorBody {
  error: {
    code: string;
    message: string;
    correlationId?: string | null;
  };
}

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
  baseUrl: string;
  getToken: GetToken;
  fetchImpl?: typeof fetch;
}

export interface ApiClient {
  getMe(): Promise<MeResponse>;
  chat(message: string): Promise<ChatResponse>;
}

export function createApiClient(options: ApiClientOptions): ApiClient {
  const doFetch = options.fetchImpl ?? fetch;

  async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
    const token = await options.getToken();
    const headers = new Headers(init.headers);
    headers.set("Content-Type", "application/json");
    if (token) {
      headers.set("Authorization", `Bearer ${token}`);
    }

    let response: Response;
    try {
      response = await doFetch(`${options.baseUrl}${path}`, { ...init, headers });
    } catch {
      throw new ApiError(0, "network_error", "Could not reach the server");
    }

    if (!response.ok) {
      let code = "http_error";
      let message = `Request failed (${response.status})`;
      let correlationId: string | null | undefined;
      try {
        const body = (await response.json()) as ApiErrorBody;
        if (body?.error) {
          code = body.error.code ?? code;
          message = body.error.message ?? message;
          correlationId = body.error.correlationId;
        }
      } catch {
        // no JSON body
      }
      throw new ApiError(response.status, code, message, correlationId);
    }

    return (await response.json()) as T;
  }

  return {
    getMe: () => request<MeResponse>("/api/v1/me"),
    chat: (message: string) =>
      request<ChatResponse>("/api/v1/chat", {
        method: "POST",
        body: JSON.stringify({ message }),
      }),
  };
}
