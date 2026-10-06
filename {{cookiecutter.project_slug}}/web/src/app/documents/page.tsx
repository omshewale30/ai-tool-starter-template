import { ChatPanel } from "@/components/ChatPanel";
import { PageHeader } from "@/components/ui/PageHeader";

export default function DocumentsPage() {
  return (
    <>
      <PageHeader title="Ask the documents">
        Answers come only from the indexed documents, with numbered sources. If the documents
        don&apos;t cover a question, the assistant says so.
      </PageHeader>
      <ChatPanel
        endpoint="/api/v1/rag/chat/stream"
        placeholder="Ask about the documents… (Shift+Enter for a new line)"
        emptyHint="Try a question your team's documents answer."
      />
    </>
  );
}
