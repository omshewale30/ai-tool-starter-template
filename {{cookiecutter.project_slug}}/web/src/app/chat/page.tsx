"use client";

import { useState, type FormEvent } from "react";

import { ErrorState } from "@/components/ErrorState";
import { Button } from "@/components/ui/Button";
import { Card } from "@/components/ui/Card";
import { EmptyState } from "@/components/ui/EmptyState";
import { Textarea } from "@/components/ui/Field";
import { PageHeader } from "@/components/ui/PageHeader";
import { Spinner } from "@/components/ui/Spinner";
import { useApiClient } from "@/lib/api/useApiClient";
import { cn } from "@/lib/cn";

interface Turn {
  role: "user" | "assistant";
  content: string;
}

export default function ChatPage() {
  const api = useApiClient();
  const [turns, setTurns] = useState<Turn[]>([]);
  const [input, setInput] = useState("");
  const [error, setError] = useState<unknown>(null);
  const [sending, setSending] = useState(false);

  async function onSubmit(event: FormEvent) {
    event.preventDefault();
    const message = input.trim();
    if (!message || sending) return;

    setError(null);
    setSending(true);
    setTurns((prev) => [...prev, { role: "user", content: message }]);
    setInput("");
    try {
      const result = await api.chat(message);
      setTurns((prev) => [...prev, { role: "assistant", content: result.response }]);
    } catch (err) {
      setError(err);
    } finally {
      setSending(false);
    }
  }

  return (
    <>
      <PageHeader title="Assistant">
        Prompts go to the API, which calls the AI model on your behalf.
      </PageHeader>
      <Card>
        <div aria-live="polite" className="mb-4 flex flex-col gap-3">
          {turns.length === 0 ? (
            <EmptyState title="No messages yet">Ask something to get started.</EmptyState>
          ) : (
            turns.map((turn, index) => (
              <div
                key={index}
                className={cn(
                  "max-w-[85%] whitespace-pre-wrap rounded-app px-4 py-3",
                  turn.role === "user"
                    ? "self-end bg-unc-bolin text-white"
                    : "self-start bg-unc-cloud text-text",
                )}
              >
                <span className="sr-only">{turn.role === "user" ? "You:" : "Assistant:"}</span>
                {turn.content}
              </div>
            ))
          )}
          {sending ? <Spinner label="Thinking…" /> : null}
        </div>
        {error ? <ErrorState error={error} /> : null}
        <form className="mt-4 flex flex-col gap-2 sm:flex-row" onSubmit={onSubmit}>
          <label htmlFor="chat-input" className="sr-only">
            Message
          </label>
          <Textarea
            id="chat-input"
            rows={2}
            placeholder="Ask a question…"
            value={input}
            onChange={(event) => setInput(event.target.value)}
            disabled={sending}
          />
          <Button type="submit" disabled={sending || input.trim().length === 0}>
            Send
          </Button>
        </form>
      </Card>
    </>
  );
}
