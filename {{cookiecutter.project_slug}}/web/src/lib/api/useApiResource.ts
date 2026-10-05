"use client";

/**
 * Loads one API resource for a component: `{ data, error, loading, reload }`.
 *
 *   const loadMe = (api: ApiClient) => api.getMe();   // module scope: stable identity
 *   const { data, error, reload } = useApiResource(loadMe);
 *
 * Pass a function defined outside the component (or memoized), otherwise the
 * request repeats on every render.
 */
import { useCallback, useEffect, useState } from "react";

import type { ApiClient } from "@/lib/api/client";
import { useApiClient } from "@/lib/api/useApiClient";

interface ResourceState<T> {
  data?: T;
  error?: unknown;
  loading: boolean;
}

export function useApiResource<T>(
  load: (api: ApiClient, signal: AbortSignal) => Promise<T>,
): ResourceState<T> & { reload: () => void } {
  const api = useApiClient();
  const [attempt, setAttempt] = useState(0);
  const [state, setState] = useState<ResourceState<T>>({ loading: true });

  useEffect(() => {
    const controller = new AbortController();
    load(api, controller.signal).then(
      (data) => {
        if (!controller.signal.aborted) setState({ data, loading: false });
      },
      (error: unknown) => {
        if (!controller.signal.aborted) setState({ error, loading: false });
      },
    );
    return () => controller.abort();
  }, [api, load, attempt]);

  const reload = useCallback(() => {
    setState({ loading: true });
    setAttempt((value) => value + 1);
  }, []);

  return { ...state, reload };
}
