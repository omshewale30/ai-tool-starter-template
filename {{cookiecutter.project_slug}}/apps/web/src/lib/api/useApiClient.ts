"use client";

/** React hook returning a backend API client wired to the current auth token. */
import { useMemo } from "react";

import { createApiClient, type ApiClient } from "@/lib/api/client";
import { useAuth } from "@/lib/auth/AuthProvider";
import { config } from "@/lib/config";

export function useApiClient(): ApiClient {
  const { getToken } = useAuth();
  return useMemo(
    () => createApiClient({ baseUrl: config.apiBaseUrl, getToken }),
    [getToken],
  );
}
