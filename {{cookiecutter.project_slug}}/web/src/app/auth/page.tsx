"use client";

/**
 * The Entra redirect URI (`<origin>/auth`, registered as a SPA redirect URI).
 *
 * MsalProvider handles the response on mount; this page only moves a signed-in
 * visitor on. Signed-out visitors see the sign-in gate from the app shell.
 */
import { useRouter } from "next/navigation";
import { useEffect } from "react";

import { Spinner } from "@/components/ui/Spinner";
import { useAuth } from "@/lib/auth/AuthProvider";

export default function AuthPage() {
  const { isReady, isAuthenticated } = useAuth();
  const router = useRouter();

  useEffect(() => {
    if (isReady && isAuthenticated) router.replace("/");
  }, [isReady, isAuthenticated, router]);

  return <Spinner label="Signing you in…" />;
}
