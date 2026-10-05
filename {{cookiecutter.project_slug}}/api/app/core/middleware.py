"""HTTP middleware: correlation ids + one structured log line per request.

Pure ASGI rather than Starlette's BaseHTTPMiddleware, so streamed responses (SSE)
pass through untouched and the logged duration covers the whole response, not
just the time to the first header.
"""

from __future__ import annotations

import re
import time
import uuid

from starlette.datastructures import MutableHeaders
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from app.core.logging import correlation_id_ctx, get_logger

logger = get_logger("app.request")

CORRELATION_HEADER = "X-Correlation-ID"
# Accept a caller's id only if it is short and plain, so it can't forge log lines.
_VALID_ID = re.compile(r"^[A-Za-z0-9._-]{1,64}$")


class CorrelationIdMiddleware:
    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        incoming = (
            dict(scope["headers"]).get(CORRELATION_HEADER.lower().encode(), b"").decode("latin-1")
        )
        correlation_id = incoming if _VALID_ID.match(incoming) else str(uuid.uuid4())
        token = correlation_id_ctx.set(correlation_id)
        start = time.perf_counter()
        status_code = 500

        async def send_with_id(message: Message) -> None:
            nonlocal status_code
            if message["type"] == "http.response.start":
                status_code = message["status"]
                MutableHeaders(scope=message).append(CORRELATION_HEADER, correlation_id)
            await send(message)

        try:
            await self.app(scope, receive, send_with_id)
        finally:
            logger.info(
                "request",
                extra={
                    "method": scope["method"],
                    "path": scope["path"],
                    "status_code": status_code,
                    "duration_ms": round((time.perf_counter() - start) * 1000, 2),
                },
            )
            correlation_id_ctx.reset(token)
