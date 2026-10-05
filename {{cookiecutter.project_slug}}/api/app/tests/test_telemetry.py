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
