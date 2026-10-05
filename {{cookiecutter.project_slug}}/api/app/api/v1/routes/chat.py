"""/api/v1/chat — prompt the configured AI model, whole or streamed.

Routes depend only on the `AIProvider` abstraction, so they behave identically with
the mock provider (local, tests) and Azure OpenAI (deployed). The streaming protocol
is described in app/services/ai/streaming.py.
"""

from __future__ import annotations

import time
from typing import Annotated

from fastapi import APIRouter, Depends
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session

from app.core.config import Settings, get_settings
from app.db.session import SessionFactory, get_db
from app.prompts import render_prompt
from app.schemas.chat import ChatRequest, ChatResponse
from app.schemas.common import ErrorResponse
from app.services.ai.base import ChatMessage
from app.services.ai.factory import AI
from app.services.ai.streaming import stream_chat_response, usage_detail
from app.services.audit import record_event
from app.services.identity.current_user import CurrentUser

router = APIRouter(tags=["chat"])

CHAT_ERROR_RESPONSES = {
    401: {"model": ErrorResponse, "description": "Missing or invalid bearer token."},
    422: {"model": ErrorResponse, "description": "Request validation failed."},
    500: {"model": ErrorResponse, "description": "Unexpected server error."},
    502: {"model": ErrorResponse, "description": "Upstream AI provider failure."},
}


def conversation(system_prompt: str, payload: ChatRequest) -> list[ChatMessage]:
    """System prompt, the client's earlier turns, then the new message."""
    history = [ChatMessage(role=turn.role, content=turn.content) for turn in payload.history]
    return [
        ChatMessage(role="system", content=system_prompt),
        *history,
        ChatMessage(role="user", content=payload.message),
    ]


def _assistant_prompt(settings: Settings) -> str:
    return render_prompt("assistant", app_name=settings.app_name)


@router.post("/chat", response_model=ChatResponse, responses=CHAT_ERROR_RESPONSES)
async def chat(
    payload: ChatRequest,
    user: CurrentUser,
    ai: AI,
    db: Annotated[Session, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> ChatResponse:
    start = time.perf_counter()
    result = await ai.chat(conversation(_assistant_prompt(settings), payload))
    record_event(
        db,
        action="chat.completed",
        actor=user,
        detail=usage_detail(ai.name, result.model, result.usage, time.perf_counter() - start),
    )
    return ChatResponse(response=result.content, model=result.model)


@router.post(
    "/chat/stream",
    responses={
        200: {"content": {"text/event-stream": {}}, "description": "Server-sent events."},
        **CHAT_ERROR_RESPONSES,
    },
)
async def chat_stream(
    payload: ChatRequest,
    user: CurrentUser,
    ai: AI,
    sessions: SessionFactory,
    settings: Annotated[Settings, Depends(get_settings)],
) -> StreamingResponse:
    return stream_chat_response(
        ai=ai,
        messages=conversation(_assistant_prompt(settings), payload),
        sessions=sessions,
        user=user,
    )
