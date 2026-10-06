import type { HTMLAttributes } from "react";

import { cn } from "@/lib/cn";

export function Card({ className, ...props }: HTMLAttributes<HTMLElement>) {
  return (
    <section
      className={cn("rounded-app border border-border bg-surface p-5 shadow-sm", className)}
      {...props}
    />
  );
}
