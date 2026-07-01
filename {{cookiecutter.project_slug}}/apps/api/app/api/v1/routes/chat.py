"""/api/v1/chat — send a prompt to the configured AI provider.

The route depends only on the `AIProvider` abstraction, so it works identically
with the mock provider (local/tests) and Azure AI Foundry (deployed).
"""
from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.config import Settings, get_settings
from app.db.session import get_db
from app.schemas.chat import ChatRequest, ChatResponse
from app.schemas.common import ErrorResponse
from app.services.ai.base import AIProvider, ChatMessage
from app.services.ai.factory import get_ai_provider
from app.services.audit import record_event
from app.services.identity.current_user import CurrentUser

router = APIRouter(tags=["chat"])

SYSTEM_PROMPT = "You are a concise, helpful assistant for an internal tool."

CHAT_ERROR_RESPONSES = {
    401: {"model": ErrorResponse, "description": "Missing or invalid bearer token."},
    422: {"model": ErrorResponse, "description": "Request validation failed."},
    500: {"model": ErrorResponse, "description": "Unexpected server error."},
    502: {"model": ErrorResponse, "description": "Upstream AI provider failure."},
}


def ai_provider(settings: Annotated[Settings, Depends(get_settings)]) -> AIProvider:
    return get_ai_provider(settings)


@router.post("/chat", response_model=ChatResponse, responses=CHAT_ERROR_RESPONSES)
async def chat(
    payload: ChatRequest,
    user: CurrentUser,
    provider: Annotated[AIProvider, Depends(ai_provider)],
    db: Annotated[Session, Depends(get_db)],
) -> ChatResponse:
    messages = [
        ChatMessage(role="system", content=SYSTEM_PROMPT),
        ChatMessage(role="user", content=payload.message),
    ]
    result = await provider.chat(messages)

    # Record that a chat happened (not the content) for auditability.
    record_event(db, action="chat.completed", actor=user, detail=f"provider={provider.name}")

    return ChatResponse(response=result.content, model=result.model)
