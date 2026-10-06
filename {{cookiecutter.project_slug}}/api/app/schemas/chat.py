"""Chat request/response schemas."""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field, field_validator

# Earlier turns are context, not input to validate strictly: an over-long one (a long
# answer the client sends back) is shortened rather than failing the whole request.
MAX_TURN_CHARS = 16000


class ChatTurn(BaseModel):
    """One earlier turn, sent by the client for multi-turn context (nothing is stored)."""

    role: Literal["user", "assistant"]
    content: str

    @field_validator("content")
    @classmethod
    def _shorten(cls, value: str) -> str:
        if len(value) <= MAX_TURN_CHARS:
            return value
        return value[:MAX_TURN_CHARS] + " […]"


class ChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=8000, examples=["Summarize this text..."])
    history: list[ChatTurn] = Field(default_factory=list, max_length=20)


class ChatResponse(BaseModel):
    response: str = Field(examples=["Here is a summary..."])
    model: str | None = None
