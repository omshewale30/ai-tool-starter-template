import { ButtonLink } from "@/components/ui/Button";
import { EmptyState } from "@/components/ui/EmptyState";

export default function NotFound() {
  return (
    <EmptyState title="Page not found">
      <p>The page you asked for doesn&apos;t exist.</p>
      <ButtonLink href="/" variant="secondary" className="mt-4">
        Go home
      </ButtonLink>
    </EmptyState>
  );
}
