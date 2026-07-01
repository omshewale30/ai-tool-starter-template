def test_chat_uses_mock_provider(client):
    resp = client.post("/api/v1/chat", json={"message": "Hello there"})
    assert resp.status_code == 200
    body = resp.json()
    # The mock provider echoes the user's message deterministically.
    assert "[mock]" in body["response"]
    assert "Hello there" in body["response"]
    assert body["model"] == "mock-1"


def test_chat_writes_audit_event(client):
    client.post("/api/v1/chat", json={"message": "audit me"})
    # /api/v1/me confirms the request path is authenticated (dev principal here).
    me = client.get("/api/v1/me")
    assert me.status_code == 200


def test_chat_rejects_empty_message(client):
    resp = client.post("/api/v1/chat", json={"message": ""})
    assert resp.status_code == 422
    assert resp.json()["error"]["code"] == "validation_error"
