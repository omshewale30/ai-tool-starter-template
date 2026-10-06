import type { InputHTMLAttributes, TextareaHTMLAttributes } from "react";

import { cn } from "@/lib/cn";

// Control borders use border-strong so the boundary clears 3:1 (WCAG 1.4.11).
const CONTROL =
  "w-full rounded-app border border-border-strong bg-surface px-3 py-2 text-base text-text " +
  "placeholder:text-muted disabled:bg-page";

export function Input({ className, ...props }: InputHTMLAttributes<HTMLInputElement>) {
  return <input className={cn(CONTROL, className)} {...props} />;
}

export function Textarea({ className, ...props }: TextareaHTMLAttributes<HTMLTextAreaElement>) {
  return <textarea className={cn(CONTROL, "resize-y", className)} {...props} />;
}
