import { ApiError } from "@/lib/api/client";

interface ErrorStateProps {
  error: unknown;
  onRetry?: () => void;
}

/** Renders a friendly error box, surfacing the backend correlation id if any. */
export function ErrorState({ error, onRetry }: ErrorStateProps) {
  const message =
    error instanceof ApiError
      ? error.message
      : error instanceof Error
        ? error.message
        : "Something went wrong.";
  const correlationId = error instanceof ApiError ? error.correlationId : undefined;

  return (
    <div className="error" role="alert">
      <strong>Error:</strong> {message}
      {correlationId ? (
        <div className="muted">
          <small>Correlation ID: {correlationId}</small>
        </div>
      ) : null}
      {onRetry ? (
        <div>
          <button className="btn btn-secondary" onClick={onRetry} type="button">
            Retry
          </button>
        </div>
      ) : null}
    </div>
  );
}
