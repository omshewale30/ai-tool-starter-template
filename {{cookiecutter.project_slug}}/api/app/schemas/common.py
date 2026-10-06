"""Shared response schemas, including the standard error envelope."""
from __future__ import annotations

from pydantic import BaseModel, Field


class ErrorDetail(BaseModel):
    code: str
    message: str
    correlationId: str | None = None


class ErrorResponse(BaseModel):
    """The consistent error envelope returned for all failures."""

    error: ErrorDetail


class HealthResponse(BaseModel):
    status: str = Field(examples=["ok"])
