"use client";

import { Button } from "@/components/ui/Button";
import { Card } from "@/components/ui/Card";
import { useAuth } from "@/lib/auth/AuthProvider";
import { SITE_NAME } from "@/lib/site";

/** Shown in place of any page until the visitor signs in. UX only; the API enforces auth. */
export function AuthGate({ redirectTo }: { redirectTo?: string }) {
  const { login } = useAuth();
  return (
    <Card className="mx-auto mt-10 max-w-md text-center">
      <h2>Sign in to {SITE_NAME}</h2>
      <p className="mt-2 text-muted">Use your UNC Onyen through Microsoft sign-in to continue.</p>
      <Button className="mt-5" onClick={() => login(redirectTo)}>
        Sign in
      </Button>
    </Card>
  );
}
