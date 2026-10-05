import type { ReactNode } from "react";

import { cn } from "@/lib/cn";

export type AlertTone = "info" | "success" | "warning" | "error";

const TONES: Record<AlertTone, string> = {
  info: "border-unc-blue bg-unc-cloud text-unc-navy",
  success: "border-success bg-success-bg text-success",
  warning: "border-warning bg-warning-bg text-warning",
  error: "border-danger bg-danger-bg text-danger",
};

/** A message box. `error` and `warning` are announced to screen readers immediately. */
export function Alert({
  tone = "info",
  title,
  children,
  className,
}: {
  tone?: AlertTone;
  title?: string;
  children?: ReactNode;
  className?: string;
}) {
  const urgent = tone === "error" || tone === "warning";
  return (
    <div
      role={urgent ? "alert" : "status"}
      className={cn("rounded-app border-l-4 px-4 py-3 text-sm", TONES[tone], className)}
    >
      {title ? <p className="font-semibold">{title}</p> : null}
      {children}
    </div>
  );
}
