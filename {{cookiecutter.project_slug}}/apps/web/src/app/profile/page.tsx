"use client";

import { useCallback, useEffect, useState } from "react";

import { ErrorState } from "@/components/ErrorState";
import { LoadingSpinner } from "@/components/LoadingSpinner";
import { useApiClient } from "@/lib/api/useApiClient";
import type { MeResponse } from "@/types";

export default function ProfilePage() {
  const api = useApiClient();
  const [me, setMe] = useState<MeResponse | null>(null);
  const [error, setError] = useState<unknown>(null);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      setMe(await api.getMe());
    } catch (err) {
      setError(err);
    } finally {
      setLoading(false);
    }
  }, [api]);

  useEffect(() => {
    void load();
  }, [load]);

  return (
    <>
      <h1>Profile</h1>
      <p className="muted">Identity and roles as resolved by the backend from your token.</p>

      <div className="card">
        {loading ? (
          <LoadingSpinner label="Loading profile…" />
        ) : error ? (
          <ErrorState error={error} onRetry={load} />
        ) : me ? (
          <dl className="kv">
            <dt>Name</dt>
            <dd>{me.name || "—"}</dd>
            <dt>Email</dt>
            <dd>{me.email || "—"}</dd>
            <dt>Subject</dt>
            <dd>{me.subject}</dd>
            <dt>Roles</dt>
            <dd>{me.roles.length ? me.roles.join(", ") : "—"}</dd>
            <dt>Groups</dt>
            <dd>{me.groups.length ? me.groups.join(", ") : "—"}</dd>
            <dt>Admin</dt>
            <dd>{me.isAdmin ? "Yes" : "No"}</dd>
          </dl>
        ) : null}
      </div>

      {me?.isDevPrincipal ? (
        <p className="muted">
          <small>
            This is a fake local-development principal (auth disabled). It does not represent a real
            signed-in user.
          </small>
        </p>
      ) : null}
    </>
  );
}
