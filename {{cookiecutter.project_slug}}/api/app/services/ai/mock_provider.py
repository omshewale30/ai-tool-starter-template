"""Deterministic mock AI provider for local development and tests.

Requires no network or credentials. It echoes a short, predictable response so
tests can assert on it and developers can exercise the full request path.
"""
from __future__ import annotations

from app.services.ai.base import AIProvider, ChatMessage, ChatResult


class MockAIProvider(AIProvider):
    name = "mock"

    async def chat(
        self,
        messages: list[ChatMessage],
        *,
        temperature: float = 0.2,
        max_tokens: int | None = None,
    ) -> ChatResult:
        last_user = next(
            (m.content for m in reversed(messages) if m.role == "user"),
            "",
        )
        preview = last_user.strip()
        if len(preview) > 200:
            preview = preview[:200] + "…"
        content = (
            f"[mock] You said: {preview}"
            if preview
            else "[mock] Hello from the mock AI provider."
        )
        return ChatResult(
            content=content,
            model="mock-1",
            metadata={"provider": self.name, "echoed_chars": len(last_user)},
        )
