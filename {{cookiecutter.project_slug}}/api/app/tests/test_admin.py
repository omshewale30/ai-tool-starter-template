from app.core.security import Principal
from app.services.identity.current_user import get_current_user


def test_admin_lists_recent_audit_events(client):
    client.post("/api/v1/chat", json={"message": "one"})
    client.post("/api/v1/chat", json={"message": "two"})

    resp = client.get("/api/v1/admin/audit-events", params={"limit": 2, "action": "chat"})

    assert resp.status_code == 200
    events = resp.json()
    assert len(events) == 2
    assert events[0]["id"] > events[1]["id"], "newest first"
    assert {e["action"] for e in events} == {"chat.completed"}
    assert events[0]["actorEmail"] == "dev@localhost"


def test_non_admins_are_refused(client):
    from app.main import app

    app.dependency_overrides[get_current_user] = lambda: Principal(
        subject="u1", name="User", email="user@unc.edu", roles=["user"], groups=[]
    )
    resp = client.get("/api/v1/admin/audit-events")
    assert resp.status_code == 403
    assert resp.json()["error"]["code"] == "forbidden"


def test_limit_is_bounded(client):
    assert client.get("/api/v1/admin/audit-events", params={"limit": 1000}).status_code == 422
