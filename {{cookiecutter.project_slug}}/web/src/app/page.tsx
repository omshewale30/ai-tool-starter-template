import { ButtonLink } from "@/components/ui/Button";
import { Card } from "@/components/ui/Card";
import { PageHeader } from "@/components/ui/PageHeader";
import { SITE_DESCRIPTION, SITE_NAME } from "@/lib/site";

export default function HomePage() {
  return (
    <>
      <PageHeader title={SITE_NAME}>{SITE_DESCRIPTION}</PageHeader>
      <div className="grid gap-4 md:grid-cols-2">
        <Card>
          <h2>Assistant</h2>
          <p className="mt-1 text-muted">
            Ask a question. Requests go through the API, which calls the AI model; the browser
            never talks to the model directly.
          </p>
          <ButtonLink href="/chat" className="mt-4">
            Open assistant
          </ButtonLink>
        </Card>
        <Card>
          <h2>Your profile</h2>
          <p className="mt-1 text-muted">
            See the identity and roles the API resolved from your access token.
          </p>
          <ButtonLink href="/profile" variant="secondary" className="mt-4">
            View profile
          </ButtonLink>
        </Card>
      </div>
    </>
  );
}
