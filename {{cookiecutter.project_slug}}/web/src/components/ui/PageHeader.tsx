import type { ReactNode } from "react";

export function PageHeader({ title, children }: { title: string; children?: ReactNode }) {
  return (
    <header className="mb-6">
      <h1>{title}</h1>
      {children ? <p className="mt-1 text-muted">{children}</p> : null}
    </header>
  );
}
