"use client";

import { useEffect, useRef, useState, type FormEvent, type KeyboardEvent } from "react";

import { Citations, type Citation } from "@/components/Citations";
import { ErrorState } from "@/components/ErrorState";
import { Button } from "@/components/ui/Button";
import { Card } from "@/components/ui/Card";
import { EmptyState } from "@/components/ui/EmptyState";
import { Textarea } from "@/components/ui/Field";
import { Markdown } from "@/components/ui/Markdown";
import { ApiError } from "@/lib/api/client";
import { readServerSentEvents } from "@/lib/api/sse";
import type { ChatTurn } from "@/lib/api/types";
import { useApiClient } from "@/lib/api/useApiClient";
import { cn } from "@/lib/cn";

interface Turn extends ChatTurn {
  status: "streaming" | "done" | "stopped" | "failed";
  citations?: Citation[];
}

/** How many earlier turns are sent for context (the API accepts up to 20). */
const HISTORY_LIMIT = 10;
/** Characters of each earlier turn sent back (the API shortens longer ones anyway). */
const HISTORY_TURN_CHARS = 8000;

interface ChatPanelProps {
  /** Streaming endpoint (see app/services/ai/streaming.py for the protocol). */
  endpoint?: string;
  placeholder?: string;
  emptyTitle?: string;
  emptyHint?: string;
}

/**
 * A streaming chat transcript and composer. Renders Markdown answers, a Stop button,
 * and the sources of grounded answers when the stream sends a `citations` event.
 * Conversations live in component state only; nothing is saved.
 */
export function ChatPanel({
  endpoint = "/api/v1/chat/stream",
  placeholder = "Ask a question… (Shift+Enter for a new line)",
  emptyTitle = "No messages yet",
  emptyHint = "Ask something to get started.",
}: ChatPanelProps) {
  const api = useApiClient();
  const [turns, setTurns] = useState<Turn[]>([]);
  const [input, setInput] = useState("");
  const [error, setError] = useState<unknown>(null);
  const [announcement, setAnnouncement] = useState("");
  const controller = useRef<AbortController | null>(null);
  const transcriptEnd = useRef<HTMLDivElement>(null);
  const streaming = turns.at(-1)?.status === "streaming";

  useEffect(() => {
    transcriptEnd.current?.scrollIntoView({ block: "end" });
  }, [turns]);

  useEffect(() => () => controller.current?.abort(), []);

  function updateLast(update: (turn: Turn) => Turn) {
    setTurns((previous) => [...previous.slice(0, -1), update(previous.at(-1)!)]);
  }

  async function send(message: string) {
    const history = turns
      .filter((turn) => turn.status === "done")
      .slice(-HISTORY_LIMIT)
      .map(({ role, content }) => ({ role, content: content.slice(0, HISTORY_TURN_CHARS) }));

    setError(null);
    setAnnouncement("");
    setTurns((previous) => [
      ...previous,
      { role: "user", content: message, status: "done" },
      { role: "assistant", content: "", status: "streaming" },
    ]);

    const abort = new AbortController();
    controller.current = abort;
    let answer = "";
    try {
      const response = await api.chatStream({ message, history }, abort.signal, endpoint);
      for await (const { event, data } of readServerSentEvents(response)) {
        if (event === "citations") {
          updateLast((turn) => ({ ...turn, citations: data as Citation[] }));
        } else if (event === "delta") {
          answer += (data as { text: string }).text;
          updateLast((turn) => ({ ...turn, content: answer }));
        } else if (event === "error") {
          const failure = data as { code: string; message: string; correlationId?: string };
          throw new ApiError(502, failure.code, failure.message, failure.correlationId);
        }
      }
      updateLast((turn) => ({ ...turn, status: "done" }));
      // Announce the finished answer once, not every token.
      setAnnouncement(`Assistant replied: ${answer}`);
    } catch (err) {
      const stopped = err instanceof DOMException && err.name === "AbortError";
      updateLast((turn) => ({ ...turn, status: stopped ? "stopped" : "failed" }));
      if (!stopped) setError(err);
    } finally {
      controller.current = null;
    }
  }

  function onSubmit(event: FormEvent) {
    event.preventDefault();
    const message = input.trim();
    if (!message || streaming) return;
    setInput("");
    void send(message);
  }

  function onKeyDown(event: KeyboardEvent<HTMLTextAreaElement>) {
    // Enter sends; Shift+Enter adds a new line.
    if (event.key === "Enter" && !event.shiftKey && !event.nativeEvent.isComposing) {
      onSubmit(event);
    }
  }

  return (
    <Card>
        <div className="mb-4 flex max-h-[60vh] flex-col gap-3 overflow-y-auto">
          {turns.length === 0 ? (
            <EmptyState title={emptyTitle}>{emptyHint}</EmptyState>
          ) : (
            turns.map((turn, index) => (
              <div
                key={index}
                className={cn(
                  "max-w-[85%] rounded-app px-4 py-3",
                  turn.role === "user"
                    ? "self-end whitespace-pre-wrap bg-unc-bolin text-white"
                    : "self-start bg-unc-cloud text-text",
                )}
              >
                <span className="sr-only">{turn.role === "user" ? "You said:" : "Assistant:"}</span>
                {turn.role === "assistant" ? (
                  <Markdown>{turn.content || (turn.status === "streaming" ? "…" : "")}</Markdown>
                ) : (
                  turn.content
                )}
                {turn.citations?.length ? <Citations citations={turn.citations} /> : null}
                {turn.status === "stopped" ? (
                  <p className="mt-1 text-xs text-muted">Stopped.</p>
                ) : null}
              </div>
            ))
          )}
          <div ref={transcriptEnd} />
        </div>
        <div role="status" aria-live="polite" className="sr-only">
          {streaming ? "Assistant is responding." : announcement}
        </div>
        {error ? <ErrorState error={error} /> : null}
        <form className="mt-4 flex flex-col gap-2 sm:flex-row sm:items-end" onSubmit={onSubmit}>
          <label htmlFor="chat-input" className="sr-only">
            Message
          </label>
          <Textarea
            id="chat-input"
            rows={2}
            placeholder={placeholder}
            value={input}
            onChange={(event) => setInput(event.target.value)}
            onKeyDown={onKeyDown}
          />
          {streaming ? (
            <Button variant="secondary" onClick={() => controller.current?.abort()}>
              Stop
            </Button>
          ) : (
            <Button type="submit" disabled={input.trim().length === 0}>
              Send
            </Button>
          )}
        </form>
    </Card>
  );
}
