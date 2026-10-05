"""/api/v1/chat — prompt the configured AI model, whole or streamed.

Routes depend only on the `AIProvider` abstraction, so they behave identically with
the mock provider (local, tests) and Azure OpenAI (deployed).

`POST /chat/stream` answers with server-sent events:

    event: delta   data: {"text": "..."}              (repeated)
    event: done    data: {"model": "...", "usage": {...}, "finishReason": "stop"}
    event: error   data: {"code": "...", "message": "...", "correlationId": "..."}

The browser reads it with fetch() (EventSource cannot send the bearer token).
"""

from __future__ import annotations

import json
import time
from collections.abc import AsyncIterator
from typing import Annotated

from fastapi import APIRouter, Depends
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session

from app.core.config import Settings, get_settings
from app.core.errors import AppError
from app.core.logging import correlation_id_ctx, get_logger
from app.core.security import Principal
from app.db.session import SessionFactory, get_db
from app.prompts import render_prompt
from app.schemas.chat import ChatRequest, ChatResponse
from app.schemas.common import ErrorResponse
from app.services.ai.base import ChatMessage, Usage
from app.services.ai.factory import AI
from app.services.audit import record_event
from app.services.identity.current_user import CurrentUser

logger = get_logger(__name__)
router = APIRouter(tags=["chat"])

CHAT_ERROR_RESPONSES = {
    401: {"model": ErrorResponse, "description": "Missing or invalid bearer token."},
    422: {"model": ErrorResponse, "description": "Request validation failed."},
    500: {"model": ErrorResponse, "description": "Unexpected server error."},
    502: {"model": ErrorResponse, "description": "Upstream AI provider failure."},
}


def _messages(payload: ChatRequest, settings: Settings) -> list[ChatMessage]:
    system = ChatMessage(
        role="system", content=render_prompt("assistant", app_name=settings.app_name)
    )
    history = [ChatMessage(role=turn.role, content=turn.content) for turn in payload.history]
    return [system, *history, ChatMessage(role="user", content=payload.message)]


def _usage_detail(provider: str, model: str | None, usage: Usage | None, elapsed: float) -> str:
    """What the audit trail keeps about an AI call: never the prompt or the answer."""
    usage = usage or Usage()
    return json.dumps(
        {
            "provider": provider,
            "model": model,
            "promptTokens": usage.prompt_tokens,
            "completionTokens": usage.completion_tokens,
            "latencyMs": round(elapsed * 1000),
        }
    )


@router.post("/chat", response_model=ChatResponse, responses=CHAT_ERROR_RESPONSES)
async def chat(
    payload: ChatRequest,
    user: CurrentUser,
    ai: AI,
    db: Annotated[Session, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> ChatResponse:
    start = time.perf_counter()
    result = await ai.chat(_messages(payload, settings))
    record_event(
        db,
        action="chat.completed",
        actor=user,
        detail=_usage_detail(ai.name, result.model, result.usage, time.perf_counter() - start),
    )
    return ChatResponse(response=result.content, model=result.model)


def _sse(event: str, data: dict) -> str:
    return f"event: {event}\ndata: {json.dumps(data)}\n\n"


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
    messages = _messages(payload, settings)

    async def events() -> AsyncIterator[str]:
        start = time.perf_counter()
        # Stays "cancelled" if the client disconnects (the generator is closed mid-stream).
        outcome, model, usage = "chat.stream_cancelled", None, None
        try:
            async for event in ai.stream_chat(messages):
                if event.type == "delta":
                    yield _sse("delta", {"text": event.text})
                else:
                    outcome, model, usage = "chat.completed", event.model, event.usage
                    yield _sse(
                        "done",
                        {
                            "model": event.model,
                            "finishReason": event.finish_reason,
                            "usage": {
                                "promptTokens": (event.usage or Usage()).prompt_tokens,
                                "completionTokens": (event.usage or Usage()).completion_tokens,
                            },
                        },
                    )
        except AppError as exc:
            outcome = "chat.stream_failed"
            # Headers are already sent, so the failure travels as an event.
            yield _sse(
                "error",
                {
                    "code": exc.code,
                    "message": exc.message,
                    "correlationId": correlation_id_ctx.get(),
                },
            )
        except Exception:  # noqa: BLE001 — never leak internals into the stream
            outcome = "chat.stream_failed"
            logger.exception("Streaming chat failed")
            yield _sse(
                "error",
                {
                    "code": "internal_error",
                    "message": "An unexpected error occurred",
                    "correlationId": correlation_id_ctx.get(),
                },
            )
        finally:
            # A fresh session: the request-scoped one is closed before the stream ends.
            _record_stream(
                sessions, user, outcome, ai.name, model, usage, time.perf_counter() - start
            )

    return StreamingResponse(
        events(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache, no-transform", "X-Accel-Buffering": "no"},
    )


def _record_stream(
    sessions: SessionFactory,
    user: Principal,
    outcome: str,
    provider: str,
    model: str | None,
    usage: Usage | None,
    elapsed: float,
) -> None:
    try:
        with sessions() as db, db.begin():
            record_event(
                db,
                action=outcome,
                actor=user,
                detail=_usage_detail(provider, model, usage, elapsed),
            )
    except Exception:  # noqa: BLE001 — auditing must not break the response
        logger.exception("Could not record the chat stream audit event")
