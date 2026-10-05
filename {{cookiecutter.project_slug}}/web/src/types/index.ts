/** Shared response types mirrored from the backend Pydantic schemas. */

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

/** The backend's consistent error envelope. */
export interface ApiErrorBody {
  error: {
    code: string;
    message: string;
    correlationId?: string | null;
  };
}
