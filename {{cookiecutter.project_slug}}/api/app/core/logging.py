"""Structured (JSON) logging with request correlation ids.

A `ContextVar` carries the current request's correlation id so any log record
emitted while handling a request is automatically stamped with it.
"""
from __future__ import annotations

import logging
from contextvars import ContextVar

from pythonjsonlogger import jsonlogger

# Set by the correlation-id middleware for the duration of each request.
correlation_id_ctx: ContextVar[str | None] = ContextVar("correlation_id", default=None)


class CorrelationIdFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        record.correlation_id = correlation_id_ctx.get()
        return True


def configure_logging(level: str = "INFO") -> None:
    """Configure root logging to emit JSON. Idempotent."""
    handler = logging.StreamHandler()
    handler.addFilter(CorrelationIdFilter())
    handler.setFormatter(
        jsonlogger.JsonFormatter(
            "%(asctime)s %(levelname)s %(name)s %(message)s %(correlation_id)s",
            rename_fields={"asctime": "timestamp", "levelname": "level"},
        )
    )

    root = logging.getLogger()
    root.handlers.clear()
    root.addHandler(handler)
    root.setLevel(level.upper())

    # Uvicorn access logs are noisy and duplicate our middleware logging.
    logging.getLogger("uvicorn.access").handlers.clear()


def get_logger(name: str) -> logging.Logger:
    return logging.getLogger(name)
