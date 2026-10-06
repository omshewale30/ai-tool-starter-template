/** An indeterminate progress indicator with an accessible label. */
export function Spinner({ label = "Loading…" }: { label?: string }) {
  return (
    <div role="status" aria-live="polite" className="flex items-center gap-2 text-sm text-muted">
      <span
        aria-hidden="true"
        className="inline-block size-5 animate-spin rounded-full border-[3px] border-border border-t-unc-bolin"
      />
      <span>{label}</span>
    </div>
  );
}
