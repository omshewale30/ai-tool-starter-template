export function LoadingSpinner({ label = "Loading…" }: { label?: string }) {
  return (
    <div role="status" aria-live="polite" className="muted">
      <span className="spinner" aria-hidden="true" /> {label}
    </div>
  );
}
