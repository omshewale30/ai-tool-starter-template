"use client";

import { useEffect } from "react";

import { ErrorState } from "@/components/ErrorState";

/** Route error boundary: keeps the shell usable when a page throws. */
export default function RouteError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    console.error(error);
  }, [error]);

  return <ErrorState error={error} onRetry={reset} />;
}
