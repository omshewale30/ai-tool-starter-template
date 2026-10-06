/** The sources a grounded answer may cite as [n] (sent as the stream's `citations` event). */
export interface Citation {
  id: number;
  title: string;
  source: string;
  snippet: string;
}

export function Citations({ citations }: { citations: Citation[] }) {
  return (
    <details className="mt-3 text-sm">
      <summary className="cursor-pointer font-semibold text-unc-bolin">
        Sources ({citations.length})
      </summary>
      <ol className="mt-2 space-y-2">
        {citations.map((citation) => (
          <li key={citation.id} className="rounded-app border border-border bg-surface p-2">
            <p className="font-semibold">
              [{citation.id}] {citation.title}
            </p>
            <p className="mt-1 text-muted">{citation.snippet}…</p>
          </li>
        ))}
      </ol>
    </details>
  );
}
