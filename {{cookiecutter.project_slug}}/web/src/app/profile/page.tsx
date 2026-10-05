"use client";

import { ErrorState } from "@/components/ErrorState";
import { Alert } from "@/components/ui/Alert";
import { Card } from "@/components/ui/Card";
import { PageHeader } from "@/components/ui/PageHeader";
import { Spinner } from "@/components/ui/Spinner";
import type { ApiClient } from "@/lib/api/client";
import { useApiResource } from "@/lib/api/useApiResource";

const loadMe = (api: ApiClient) => api.getMe();

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="grid grid-cols-[8rem_1fr] gap-4 py-2">
      <dt className="text-muted">{label}</dt>
      <dd className="break-words">{value || "—"}</dd>
    </div>
  );
}

export default function ProfilePage() {
  const { data: me, error, reload } = useApiResource(loadMe);

  return (
    <>
      <PageHeader title="Profile">Your identity and roles, as the API sees them.</PageHeader>
      {me?.isDevPrincipal ? (
        <Alert tone="warning" className="mb-4">
          This is a fake local-development identity (sign-in is disabled).
        </Alert>
      ) : null}
      <Card>
        {error ? (
          <ErrorState error={error} onRetry={reload} />
        ) : !me ? (
          <Spinner label="Loading profile…" />
        ) : (
          <dl className="divide-y divide-border">
            <Row label="Name" value={me.name} />
            <Row label="Email" value={me.email} />
            <Row label="Object ID" value={me.subject} />
            <Row label="App roles" value={me.roles.join(", ")} />
            <Row label="Admin" value={me.isAdmin ? "Yes" : "No"} />
          </dl>
        )}
      </Card>
    </>
  );
}
