"""Turn an AI stream into a server-sent-events response, and audit it afterwards.

Every streaming route uses `stream_chat_response`, so they all speak the same
protocol to the browser (web/src/lib/api/sse.ts):

    event: <leading events, e.g. citations>   (optional, sent first)
    event: delta   data: {"text": "..."}              (repeated)
    event: done    data: {"model": "...", "usage": {...}, "finishReason": "stop"}
    event: error   data: {"code": "...", "message": "...", "correlationId": "..."}

The audit event is written after the stream ends, with a fresh session (the
request-scoped one is closed by then), and records usage, never content.
"""

from __future__ import annotations

import json
from collections.abc import AsyncIterator, Sequence
from typing import Any

from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session, sessionmaker

from app.core.errors import AppError
from app.core.logging import correlation_id_ctx, get_logger
from app.core.security import Principal
from app.services.ai.base import AIProvider, ChatMessage, Usage
from app.services.audit import record_event
from app.services.telemetry import AISpan

logger = get_logger(__name__)

SSE_HEADERS = {"Cache-Control": "no-cache, no-transform", "X-Accel-Buffering": "no"}


def sse(event: str, data: Any) -> str:
    return f"event: {event}\ndata: {json.dumps(data)}\n\n"


def usage_detail(provider: str, model: str | None, usage: Usage | None, elapsed: float) -> str:
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


def _error(code: str, message: str) -> str:
    return sse(
        "error", {"code": code, "message": message, "correlationId": correlation_id_ctx.get()}
    )


def stream_chat_response(
    *,
    ai: AIProvider,
    messages: list[ChatMessage],
    sessions: sessionmaker[Session],
    user: Principal,
    action: str = "chat",
    leading_events: Sequence[tuple[str, Any]] = (),
) -> StreamingResponse:
    """Stream `ai.stream_chat(messages)` as SSE; audit `<action>.completed|failed|cancelled`."""

    async def events() -> AsyncIterator[str]:
        span = AISpan(f"{action}.stream", provider=ai.name)
        failure: BaseException | None = None
        # Stays "cancelled" if the client disconnects (the generator is closed mid-stream).
        outcome, model, usage = f"{action}.stream_cancelled", None, None
        try:
            for name, data in leading_events:
                yield sse(name, data)
            async for event in ai.stream_chat(messages):
                if event.type == "delta":
                    yield sse("delta", {"text": event.text})
                    continue
                outcome, model, usage = f"{action}.completed", event.model, event.usage
                reported = event.usage or Usage()
                yield sse(
                    "done",
                    {
                        "model": event.model,
                        "finishReason": event.finish_reason,
                        "usage": {
                            "promptTokens": reported.prompt_tokens,
                            "completionTokens": reported.completion_tokens,
                        },
                    },
                )
        except AppError as exc:
            outcome, failure = f"{action}.stream_failed", exc
            # Headers are already sent, so the failure travels as an event.
            yield _error(exc.code, exc.message)
        except Exception as exc:  # noqa: BLE001 — never leak internals into the stream
            outcome, failure = f"{action}.stream_failed", exc
            logger.exception("Streaming %s failed", action)
            yield _error("internal_error", "An unexpected error occurred")
        finally:
            if outcome.endswith(".completed"):
                span.finish(model=model, usage=usage)
            else:
                span.fail(failure, outcome=outcome.rsplit(".", 1)[-1])
            _record(sessions, user, outcome, usage_detail(ai.name, model, usage, span.elapsed))

    return StreamingResponse(events(), media_type="text/event-stream", headers=SSE_HEADERS)


def _record(sessions: sessionmaker[Session], user: Principal, action: str, detail: str) -> None:
    try:
        with sessions() as db, db.begin():
            record_event(db, action=action, actor=user, detail=detail)
    except Exception:  # noqa: BLE001 — auditing must not break the response
        logger.exception("Could not record the %s audit event", action)
