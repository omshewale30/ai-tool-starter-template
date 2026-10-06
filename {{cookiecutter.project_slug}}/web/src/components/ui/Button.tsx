import Link from "next/link";
import type { ButtonHTMLAttributes, ComponentProps } from "react";

import { cn } from "@/lib/cn";

export type ButtonVariant = "primary" | "secondary" | "ghost" | "danger";

const BASE =
  "inline-flex min-h-10 items-center justify-center gap-2 rounded-app px-4 py-2 text-sm font-semibold " +
  "no-underline transition-colors hover:no-underline disabled:cursor-not-allowed disabled:opacity-60";

const VARIANTS: Record<ButtonVariant, string> = {
  // White on Bolin Creek (8.1:1); hover darkens to Navy.
  primary: "bg-unc-bolin text-white hover:bg-unc-navy",
  secondary: "border border-unc-bolin bg-surface text-unc-bolin hover:bg-unc-cloud",
  ghost: "text-unc-bolin hover:bg-unc-cloud",
  danger: "bg-danger text-white hover:bg-[#912018]",
};

export function buttonClasses(variant: ButtonVariant = "primary", className?: string): string {
  return cn(BASE, VARIANTS[variant], className);
}

export function Button({
  variant = "primary",
  className,
  type = "button",
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & { variant?: ButtonVariant }) {
  return <button type={type} className={buttonClasses(variant, className)} {...props} />;
}

export function ButtonLink({
  variant = "primary",
  className,
  ...props
}: ComponentProps<typeof Link> & { variant?: ButtonVariant }) {
  return <Link className={buttonClasses(variant, className)} {...props} />;
}
