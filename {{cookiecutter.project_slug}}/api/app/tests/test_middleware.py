def test_a_plain_caller_correlation_id_is_echoed(client):
    resp = client.get("/health/live", headers={"X-Correlation-ID": "abc-123"})
    assert resp.headers["X-Correlation-ID"] == "abc-123"


def test_an_unsafe_correlation_id_is_replaced(client):
    resp = client.get("/health/live", headers={"X-Correlation-ID": "x\ninjected log line"})
    assert resp.headers["X-Correlation-ID"] != "x\ninjected log line"
    assert len(resp.headers["X-Correlation-ID"]) == 36  # a fresh uuid4


def test_error_envelope_carries_the_same_correlation_id(client):
    resp = client.post("/api/v1/chat", json={}, headers={"X-Correlation-ID": "trace-1"})
    assert resp.status_code == 422
    assert resp.json()["error"]["correlationId"] == "trace-1"
