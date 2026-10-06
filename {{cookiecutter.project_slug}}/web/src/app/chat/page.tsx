import { ChatPanel } from "@/components/ChatPanel";
import { PageHeader } from "@/components/ui/PageHeader";

export default function ChatPage() {
  return (
    <>
      <PageHeader title="Assistant">
        Prompts go to the API, which calls the AI model on your behalf. Conversations are not
        saved.
      </PageHeader>
      <ChatPanel />
    </>
  );
}
