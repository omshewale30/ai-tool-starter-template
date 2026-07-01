"use client";

import { useState } from "react";

import { ErrorState } from "@/components/ErrorState";
import { LoadingSpinner } from "@/components/LoadingSpinner";
import { useApiClient } from "@/lib/api/useApiClient";

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

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
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
      <h1>Assistant</h1>
      <p className="muted">
        Prompts are sent to the backend, which calls the AI provider. The frontend never talks to
        the AI service directly.
      </p>

      <div className="card">
        <div className="chat-log">
          {turns.length === 0 ? (
            <p className="muted">Ask something to get started.</p>
          ) : (
            turns.map((turn, i) => (
              <div key={i} className={turn.role === "user" ? "msg msg-user" : "msg msg-assistant"}>
                {turn.content}
              </div>
            ))
          )}
          {sending ? <LoadingSpinner label="Thinking…" /> : null}
        </div>

        {error ? <ErrorState error={error} /> : null}

        <form className="chat-form" onSubmit={onSubmit}>
          <input
            className="input"
            aria-label="Message"
            placeholder="Summarize this text..."
            value={input}
            onChange={(e) => setInput(e.target.value)}
            disabled={sending}
          />
          <button className="btn" type="submit" disabled={sending || input.trim().length === 0}>
            Send
          </button>
        </form>
      </div>
    </>
  );
}
