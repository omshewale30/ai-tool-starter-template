"""The AI provider abstraction.

Routes and services depend only on `AIProvider`. Concrete providers (mock, Azure
OpenAI / AI Foundry) implement it. This keeps privileged AI access on the backend
and makes local development and tests possible without any Azure dependency.

Four capabilities cover most tools:
  - `chat`         one complete response
  - `stream_chat`  the same, as incremental events (for responsive UIs)
  - `complete_json` a response validated into a Pydantic model (extraction,
                   classification, any "fill in this structure" task)
  - `embed`        vectors for similarity search and RAG
"""

from __future__ import annotations

import json
from abc import ABC, abstractmethod
from collections.abc import AsyncIterator
from dataclasses import dataclass, field
from typing import Literal, TypeVar

from pydantic import BaseModel, ValidationError

from app.core.errors import UpstreamServiceError

Role = Literal["system", "user", "assistant"]
ModelT = TypeVar("ModelT", bound=BaseModel)


@dataclass
class ChatMessage:
    role: Role
    content: str


@dataclass
class Usage:
    prompt_tokens: int | None = None
    completion_tokens: int | None = None

    @property
    def total_tokens(self) -> int | None:
        if self.prompt_tokens is None or self.completion_tokens is None:
            return None
        return self.prompt_tokens + self.completion_tokens


@dataclass
class ChatResult:
    content: str
    model: str
    usage: Usage = field(default_factory=Usage)
    finish_reason: str | None = None


@dataclass
class StreamEvent:
    """One event of a streamed response.

    `delta` carries the next piece of text; `done` is always last and carries the
    model, usage (when the provider reports it) and finish reason.
    """

    type: Literal["delta", "done"]
    text: str = ""
    model: str | None = None
    usage: Usage | None = None
    finish_reason: str | None = None


class AIProvider(ABC):
    """Backend-only interface for AI models."""

    name: str = "base"

    @abstractmethod
    async def chat(
        self,
        messages: list[ChatMessage],
        *,
        temperature: float | None = None,
        max_tokens: int | None = None,
        json_mode: bool = False,
    ) -> ChatResult:
        """Return one complete assistant response."""

    @abstractmethod
    def stream_chat(
        self,
        messages: list[ChatMessage],
        *,
        temperature: float | None = None,
        max_tokens: int | None = None,
    ) -> AsyncIterator[StreamEvent]:
        """Yield `delta` events as text arrives, then exactly one `done` event."""

    @abstractmethod
    async def embed(self, texts: list[str]) -> list[list[float]]:
        """Return one embedding vector per input text, in order."""

    async def complete_json(
        self,
        messages: list[ChatMessage],
        schema: type[ModelT],
        *,
        temperature: float | None = 0.0,
    ) -> ModelT:
        """Ask for JSON matching `schema` and return it validated.

        The schema is appended to the system instructions and the model is put in
        JSON mode; the reply is validated with Pydantic, so callers get a typed
        object or an `UpstreamServiceError`, never half-parsed text.
        """
        instructions = ChatMessage(
            role="system",
            content=(
                "Respond with a single JSON object that conforms to this JSON Schema. "
                "Output only the JSON, with no surrounding text.\n"
                + json.dumps(schema.model_json_schema())
            ),
        )
        result = await self.chat([*messages, instructions], temperature=temperature, json_mode=True)
        try:
            return schema.model_validate_json(result.content)
        except ValidationError as exc:
            raise UpstreamServiceError("The AI response did not match the expected format") from exc
