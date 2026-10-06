"""Deterministic mock AI provider for local development and tests.

Requires no network or credentials. Chat echoes the last user message so tests can
assert on it and developers can exercise the full request path; streaming yields
it word by word; embeddings are stable hash-derived vectors.

JSON mode returns `{}` unless a canned response is registered for that request:

    MockAIProvider.json_responses.append('{"category": "travel"}')
"""

from __future__ import annotations

import asyncio
import hashlib
from collections.abc import AsyncIterator

from app.services.ai.base import AIProvider, ChatMessage, ChatResult, StreamEvent, Usage

MOCK_MODEL = "mock-1"
EMBEDDING_DIMENSIONS = 16


def _reply_to(messages: list[ChatMessage]) -> str:
    last_user = next((m.content for m in reversed(messages) if m.role == "user"), "")
    preview = last_user.strip()
    if len(preview) > 200:
        preview = preview[:200] + "…"
    return f"[mock] You said: {preview}" if preview else "[mock] Hello from the mock AI provider."


def _usage(messages: list[ChatMessage], reply: str) -> Usage:
    # A rough word count stands in for tokens, so usage plumbing is exercised.
    prompt = sum(len(m.content.split()) for m in messages)
    return Usage(prompt_tokens=prompt, completion_tokens=len(reply.split()))


class MockAIProvider(AIProvider):
    name = "mock"
    # Canned JSON-mode replies, consumed first in, first out (tests append to this).
    json_responses: list[str] = []

    async def chat(
        self,
        messages: list[ChatMessage],
        *,
        temperature: float | None = None,
        max_tokens: int | None = None,
        json_mode: bool = False,
    ) -> ChatResult:
        if json_mode:
            content = self.json_responses.pop(0) if self.json_responses else "{}"
        else:
            content = _reply_to(messages)
        return ChatResult(
            content=content, model=MOCK_MODEL, usage=_usage(messages, content), finish_reason="stop"
        )

    async def stream_chat(
        self,
        messages: list[ChatMessage],
        *,
        temperature: float | None = None,
        max_tokens: int | None = None,
    ) -> AsyncIterator[StreamEvent]:
        reply = _reply_to(messages)
        words = reply.split(" ")
        for index, word in enumerate(words):
            yield StreamEvent(type="delta", text=word if index == 0 else f" {word}")
            await asyncio.sleep(0)  # let the server flush, as a real stream would
        yield StreamEvent(
            type="done", model=MOCK_MODEL, usage=_usage(messages, reply), finish_reason="stop"
        )

    async def embed(self, texts: list[str]) -> list[list[float]]:
        vectors = []
        for text in texts:
            digest = hashlib.sha256(text.encode("utf-8")).digest()
            vectors.append([byte / 255 for byte in digest[:EMBEDDING_DIMENSIONS]])
        return vectors
