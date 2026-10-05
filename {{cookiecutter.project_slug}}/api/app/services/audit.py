"""Service for recording important events to the audit trail.

Kept deliberately simple — a couple of module-level functions rather than a
repository class. Add a repository only if the query surface grows.
"""
from __future__ import annotations

from sqlalchemy.orm import Session

from app.core.logging import correlation_id_ctx
from app.core.security import Principal
from app.models.audit_event import AuditEvent


def record_event(
    db: Session,
    *,
    action: str,
    actor: Principal,
    detail: str = "",
) -> AuditEvent:
    """Append an audit event. The caller's transaction commits it."""
    event = AuditEvent(
        action=action,
        actor_subject=actor.subject,
        actor_email=actor.email,
        detail=detail,
        correlation_id=correlation_id_ctx.get(),
    )
    db.add(event)
    db.flush()  # assign PK without ending the request transaction
    return event
