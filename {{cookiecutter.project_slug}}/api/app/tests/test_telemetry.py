import os
import subprocess
import sys
from pathlib import Path

import fastapi

from app.core.config import Settings
from app.main import create_app
from app.services.ai.base import Usage
from app.services.telemetry import AISpan, configure_telemetry


def test_create_app_uses_the_class_instrumentation_installs(monkeypatch):
    """Azure Monitor's FastAPI instrumentation swaps `fastapi.FastAPI` for a subclass;
    create_app must pick that up rather than a reference imported earlier."""

    class Instrumented(fastapi.FastAPI):
        pass

    monkeypatch.setattr(fastapi, "FastAPI", Instrumented)
    assert isinstance(create_app(), Instrumented)


def test_telemetry_is_off_without_a_connection_string():
    assert configure_telemetry(Settings(environment="test")) is False


def test_ai_spans_are_safe_without_telemetry():
    span = AISpan("chat", provider="mock")
    span.finish(model="mock-1", usage=Usage(prompt_tokens=3, completion_tokens=2))
    AISpan("chat", provider="mock").fail(RuntimeError("boom"))
    assert span.elapsed >= 0


def test_a_configured_connection_string_instruments_the_real_app():
    """End to end through configure_azure_monitor, in a fresh interpreter (instrumentation
    is process-global). The ingestion endpoint is unroutable; nothing is sent."""
    script = (
        "import os, sys\n"
        "from app.main import app\n"
        "sys.stdout.write(type(app).__name__)\n"
        "sys.stdout.flush()\n"
        "os._exit(0)\n"  # skip exporter shutdown flushes
    )
    env = {
        **os.environ,
        "ENVIRONMENT": "test",
        "AUTH_MODE": "disabled",
        "DATABASE_URL": "sqlite+pysqlite:///:memory:",
        "APPLICATIONINSIGHTS_CONNECTION_STRING": (
            "InstrumentationKey=00000000-0000-0000-0000-000000000000;"
            "IngestionEndpoint=https://127.0.0.1/"
        ),
    }
    result = subprocess.run(
        [sys.executable, "-c", script],
        cwd=Path(__file__).resolve().parents[2],
        env=env,
        capture_output=True,
        text=True,
        timeout=120,
        check=False,
    )
    assert result.stdout == "_InstrumentedFastAPI", result.stderr[-2000:]
