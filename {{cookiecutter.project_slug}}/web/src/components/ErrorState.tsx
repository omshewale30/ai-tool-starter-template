import { Alert } from "@/components/ui/Alert";
import { Button } from "@/components/ui/Button";
import { ApiError } from "@/lib/api/client";

interface ErrorStateProps {
  error: unknown;
  onRetry?: () => void;
}

/** A friendly error box that surfaces the backend correlation id for support requests. */
export function ErrorState({ error, onRetry }: ErrorStateProps) {
  const message =
    error instanceof ApiError || error instanceof Error ? error.message : "Something went wrong.";
  const correlationId = error instanceof ApiError ? error.correlationId : undefined;

  return (
    <Alert tone="error" title="Error">
      <p>{message}</p>
      {correlationId ? (
        <p className="mt-1 text-xs">
          Reference: <code>{correlationId}</code>
        </p>
      ) : null}
      {onRetry ? (
        <Button variant="secondary" className="mt-3" onClick={onRetry}>
          Retry
        </Button>
      ) : null}
    </Alert>
  );
}
