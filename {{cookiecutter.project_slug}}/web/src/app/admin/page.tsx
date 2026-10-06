"use client";

import { ErrorState } from "@/components/ErrorState";
import { Card } from "@/components/ui/Card";
import { EmptyState } from "@/components/ui/EmptyState";
import { PageHeader } from "@/components/ui/PageHeader";
import { Spinner } from "@/components/ui/Spinner";
import type { ApiClient } from "@/lib/api/client";
import type { AuditEvent } from "@/lib/api/types";
import { useApiResource } from "@/lib/api/useApiResource";

const loadEvents = (api: ApiClient) =>
  api.request<AuditEvent[]>("/api/v1/admin/audit-events?limit=100");

/** Usage, model and latency of an AI call, from the audit event's JSON detail. */
function summarize(detail: string): string {
  try {
    const usage = JSON.parse(detail) as Record<string, string | number | null>;
    const tokens = [usage.promptTokens, usage.completionTokens].every((v) => v != null)
      ? `${usage.promptTokens} in / ${usage.completionTokens} out`
      : "";
    return [usage.model, tokens, usage.latencyMs != null ? `${usage.latencyMs} ms` : ""]
      .filter(Boolean)
      .join(" · ");
  } catch {
    return detail;
  }
}

/**
 * A minimal operational view: recent audit events, including every AI call's model,
 * tokens and latency. The API enforces the admin role; this page only displays.
 */
export default function AdminPage() {
  const { data: events, error, reload } = useApiResource(loadEvents);

  return (
    <>
      <PageHeader title="Admin">Recent activity, newest first.</PageHeader>
      <Card>
        {error ? (
          <ErrorState error={error} onRetry={reload} />
        ) : !events ? (
          <Spinner label="Loading activity…" />
        ) : events.length === 0 ? (
          <EmptyState title="No activity yet" />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-left text-sm">
              <caption className="sr-only">Recent audit events</caption>
              <thead className="border-b border-border-strong text-muted">
                <tr>
                  <th scope="col" className="py-2 pr-4">When</th>
                  <th scope="col" className="py-2 pr-4">Action</th>
                  <th scope="col" className="py-2 pr-4">User</th>
                  <th scope="col" className="py-2">Details</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border">
                {events.map((event) => (
                  <tr key={event.id}>
                    <td className="py-2 pr-4 whitespace-nowrap">
                      {new Date(event.createdAt).toLocaleString()}
                    </td>
                    <td className="py-2 pr-4">{event.action}</td>
                    <td className="py-2 pr-4">{event.actorEmail}</td>
                    <td className="py-2">{summarize(event.detail)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>
    </>
  );
}
