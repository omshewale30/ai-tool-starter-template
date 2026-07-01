"""Verify the consistent error envelope shape across error types."""


def _assert_envelope(body: dict, code: str):
    assert set(body.keys()) == {"error"}
    err = body["error"]
    assert err["code"] == code
    assert isinstance(err["message"], str) and err["message"]
    assert "correlationId" in err


def test_not_found_envelope(client):
    resp = client.get("/api/v1/does-not-exist")
    assert resp.status_code == 404
    _assert_envelope(resp.json(), "not_found")


def test_validation_error_envelope(client):
    resp = client.post("/api/v1/chat", json={})  # missing required 'message'
    assert resp.status_code == 422
    _assert_envelope(resp.json(), "validation_error")


def test_correlation_id_is_populated(client):
    resp = client.get("/api/v1/does-not-exist")
    assert resp.json()["error"]["correlationId"]
