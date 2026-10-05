"""Azure Monitor (Application Insights) via OpenTelemetry. Minimal on purpose.

What you get when APPLICATIONINSIGHTS_CONNECTION_STRING is set (it is bound from Key
Vault in Azure; unset locally, which makes everything here a no-op):
  - a request span per HTTP call (FastAPI) and dependency spans for outgoing HTTP
    (httpx/requests, including Azure OpenAI and Azure SDK calls) and the database;
  - logs from the `app.*` loggers, correlated with the request that emitted them;
  - one `ai.<operation>` span per model call with model, token usage and outcome
    (`AISpan`), so App Insights can chart AI latency and token use per operation.

Extend here: custom metrics (opentelemetry.metrics), sampling
(OTEL_TRACES_SAMPLER / OTEL_TRACES_SAMPLER_ARG), or browser telemetry.
"""

from __future__ import annotations

import os
import time
from typing import TYPE_CHECKING

from opentelemetry import trace
from opentelemetry.trace import Status, StatusCode

from app.core.logging import get_logger

if TYPE_CHECKING:
    from app.core.config import Settings
    from app.services.ai.base import Usage

logger = get_logger(__name__)
_tracer = trace.get_tracer("app.ai")


def configure_telemetry(settings: Settings) -> bool:
    """Wire Azure Monitor if configured. Call BEFORE the FastAPI app is created.

    The FastAPI instrumentation patches the FastAPI class, so an app instantiated
    first is never instrumented. Never raises: telemetry must not block startup.
    """
    if not settings.applicationinsights_connection_string:
        return False
    # Probes would dominate the request table; leave them out.
    os.environ.setdefault("OTEL_PYTHON_FASTAPI_EXCLUDED_URLS", "health/.*,api/health,healthz")
    os.environ.setdefault("OTEL_SERVICE_NAME", f"{settings.app_name} API")
    try:
        from azure.monitor.opentelemetry import configure_azure_monitor

        configure_azure_monitor(
            connection_string=settings.applicationinsights_connection_string,
            logger_name="app",
            enable_live_metrics=False,
        )
    except Exception:  # noqa: BLE001
        logger.exception("Azure Monitor could not be configured; continuing without it")
        return False
    logger.info("Azure Monitor OpenTelemetry enabled")
    return True


class AISpan:
    """Times one model call as an `ai.<operation>` span (a no-op without telemetry).

        span = AISpan("chat", provider=ai.name)
        ...
        span.finish(model=result.model, usage=result.usage)       # or span.fail(exc)

    Not a context manager on purpose: a streamed response finishes in a generator,
    after the request handler has returned.
    """

    def __init__(self, operation: str, *, provider: str):
        self._start = time.perf_counter()
        self._span = _tracer.start_span(
            f"ai.{operation}",
            kind=trace.SpanKind.CLIENT,
            attributes={"gen_ai.operation.name": operation, "gen_ai.system": provider},
        )

    @property
    def elapsed(self) -> float:
        return time.perf_counter() - self._start

    def finish(self, *, model: str | None, usage: Usage | None, outcome: str = "completed") -> None:
        attributes: dict[str, str | int] = {"ai.outcome": outcome}
        if model:
            attributes["gen_ai.response.model"] = model
        if usage and usage.prompt_tokens is not None:
            attributes["gen_ai.usage.input_tokens"] = usage.prompt_tokens
        if usage and usage.completion_tokens is not None:
            attributes["gen_ai.usage.output_tokens"] = usage.completion_tokens
        self._span.set_attributes(attributes)
        self._span.end()

    def fail(self, error: BaseException | None = None, *, outcome: str = "failed") -> None:
        self._span.set_attribute("ai.outcome", outcome)
        if error is not None:
            self._span.record_exception(error)
        self._span.set_status(Status(StatusCode.ERROR))
        self._span.end()
