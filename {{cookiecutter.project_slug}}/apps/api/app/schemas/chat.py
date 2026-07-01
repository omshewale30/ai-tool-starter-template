"""Chat request/response schemas."""
from __future__ import annotations

from pydantic import BaseModel, Field


class ChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=8000, examples=["Summarize this text..."])


class ChatResponse(BaseModel):
    response: str = Field(examples=["Here is a summary..."])
    model: str | None = None
