"""Chat request/response schemas."""
from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field


class ChatTurn(BaseModel):
    """One earlier turn, sent by the client for multi-turn context (nothing is stored)."""

    role: Literal["user", "assistant"]
    content: str = Field(max_length=16000)


class ChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=8000, examples=["Summarize this text..."])
    history: list[ChatTurn] = Field(default_factory=list, max_length=20)


class ChatResponse(BaseModel):
    response: str = Field(examples=["Here is a summary..."])
    model: str | None = None
