def test_live(client):
    resp = client.get("/health/live")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}


def test_ready(client):
    resp = client.get("/health/ready")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"
    # Correlation id is echoed back for traceability.
    assert resp.headers.get("X-Correlation-ID")


def test_deployment_health_reports_booleans_only(client):
    resp = client.get("/api/health")
    assert resp.status_code == 200
    assert resp.headers["Cache-Control"] == "no-store"
    body = resp.json()
    # Test settings: mock AI, auth disabled, in-memory SQLite.
    assert body == {
        "status": "ok",
        "environment": "test",
        "database": "ok",
        "auth": {"mode": "disabled", "configured": False},
        "ai": {"provider": "mock", "configured": True},
    }


def test_deployment_health_degrades_when_entra_is_unconfigured(client):
    from app.core.config import AuthMode, get_settings
    from app.main import app

    entra_unconfigured = get_settings().model_copy(
        update={"auth_mode": AuthMode.entra, "azure_tenant_id": ""}
    )
    app.dependency_overrides[get_settings] = lambda: entra_unconfigured
    try:
        body = client.get("/api/health").json()
    finally:
        app.dependency_overrides.pop(get_settings, None)

    assert body["status"] == "degraded"
    assert body["auth"] == {"mode": "entra", "configured": False}
