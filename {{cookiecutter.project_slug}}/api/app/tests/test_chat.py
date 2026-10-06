import json

from app.models.audit_event import AuditEvent
from app.services.ai.base import AIProvider
from app.services.ai.factory import _provider_dependency
from app.services.ai.mock_provider import MockAIProvider


def parse_sse(text: str) -> list[tuple[str, dict]]:
    events = []
    for block in text.strip().split("\n\n"):
        lines = dict(line.split(": ", 1) for line in block.splitlines())
        events.append((lines["event"], json.loads(lines["data"])))
    return events


def test_chat_uses_mock_provider(client):
    resp = client.post("/api/v1/chat", json={"message": "Hello there"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["response"] == "[mock] You said: Hello there"
    assert body["model"] == "mock-1"


def test_chat_records_usage_but_not_content(client, db_session):
    client.post("/api/v1/chat", json={"message": "secret quarterly numbers"})
    event = (
        db_session.query(AuditEvent)
        .filter_by(action="chat.completed")
        .order_by(AuditEvent.id.desc())
        .first()
    )
    detail = json.loads(event.detail)
    assert detail["provider"] == "mock" and detail["model"] == "mock-1"
    assert detail["promptTokens"] > 0 and detail["completionTokens"] > 0
    assert "secret" not in event.detail


def test_chat_rejects_empty_message(client):
    resp = client.post("/api/v1/chat", json={"message": ""})
    assert resp.status_code == 422
    assert resp.json()["error"]["code"] == "validation_error"


def test_chat_passes_client_history_to_the_model(client):
    captured = {}

    class Recording(MockAIProvider):
        async def chat(self, messages, **kwargs):
            captured["roles"] = [m.role for m in messages]
            return await super().chat(messages, **kwargs)

    client.app.dependency_overrides[_provider_dependency] = lambda: Recording()
    client.post(
        "/api/v1/chat",
        json={
            "message": "and now?",
            "history": [
                {"role": "user", "content": "hi"},
                {"role": "assistant", "content": "hello"},
            ],
        },
    )
    assert captured["roles"] == ["system", "user", "assistant", "user"]


def test_stream_emits_deltas_then_done(client):
    resp = client.post("/api/v1/chat/stream", json={"message": "Hello there"})
    assert resp.status_code == 200
    assert resp.headers["content-type"].startswith("text/event-stream")
    assert resp.headers["X-Correlation-ID"]

    events = parse_sse(resp.text)
    deltas = [data["text"] for name, data in events if name == "delta"]
    assert "".join(deltas) == "[mock] You said: Hello there"
    assert len(deltas) > 1, "the answer should arrive in pieces"
    name, done = events[-1]
    assert name == "done"
    assert done["model"] == "mock-1"
    assert done["usage"]["completionTokens"] == 5


def test_stream_records_an_audit_event_after_the_stream(client, db_session):
    client.post("/api/v1/chat/stream", json={"message": "count me"})
    db_session.expire_all()
    events = db_session.query(AuditEvent).filter_by(action="chat.completed").all()
    assert any(json.loads(e.detail)["completionTokens"] for e in events)


def test_stream_reports_provider_failure_as_an_error_event(client, db_session):
    from app.core.errors import UpstreamServiceError

    class Failing(MockAIProvider):
        async def stream_chat(self, messages, **kwargs):
            yield await anext(super().stream_chat(messages, **kwargs))
            raise UpstreamServiceError("AI service request failed")

    client.app.dependency_overrides[_provider_dependency] = lambda: Failing()
    resp = client.post("/api/v1/chat/stream", json={"message": "boom"})

    events = parse_sse(resp.text)
    assert events[0][0] == "delta"
    name, error = events[-1]
    assert name == "error"
    assert error["code"] == "upstream_error"
    assert error["correlationId"] == resp.headers["X-Correlation-ID"]
    db_session.expire_all()
    assert db_session.query(AuditEvent).filter_by(action="chat.stream_failed").count() >= 1


def test_stream_requires_a_valid_request(client):
    resp = client.post("/api/v1/chat/stream", json={"message": ""})
    assert resp.status_code == 422


def test_provider_dependency_is_overridable_for_any_provider(client):
    assert issubclass(MockAIProvider, AIProvider)


def test_an_over_long_history_turn_is_shortened_not_rejected(client):
    captured = {}

    class Recording(MockAIProvider):
        async def chat(self, messages, **kwargs):
            captured["assistant"] = messages[2].content
            return await super().chat(messages, **kwargs)

    client.app.dependency_overrides[_provider_dependency] = lambda: Recording()
    long_answer = "x" * 50_000
    resp = client.post(
        "/api/v1/chat",
        json={
            "message": "follow-up",
            "history": [
                {"role": "user", "content": "write a lot"},
                {"role": "assistant", "content": long_answer},
            ],
        },
    )
    assert resp.status_code == 200
    assert len(captured["assistant"]) < 17_000
    assert captured["assistant"].endswith("[…]")
