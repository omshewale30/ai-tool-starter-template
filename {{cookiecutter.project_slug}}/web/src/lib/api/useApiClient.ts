"use client";

/** React hook returning an API client wired to the signed-in user's token. */
import { useMemo } from "react";

import { createApiClient, type ApiClient } from "@/lib/api/client";
import { useAuth } from "@/lib/auth/AuthProvider";

export function useApiClient(): ApiClient {
  const { getToken } = useAuth();
  return useMemo(() => createApiClient({ getToken }), [getToken]);
}
