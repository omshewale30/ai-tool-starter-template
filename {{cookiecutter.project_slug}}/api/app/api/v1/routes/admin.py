"""/api/v1/admin/* — routes gated by the `admin` app role (or ADMIN_GROUP_ID).

A starting point for operational views. The audit trail already records every AI
call's outcome, model, token usage and latency (never prompts or answers), so usage
reporting can be built from it; add a dedicated table (with a migration) when a tool
needs quotas, cost reports, or feedback.
"""

from __future__ import annotations

from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.audit_event import AuditEvent
from app.schemas.common import ErrorResponse
from app.services.identity.current_user import AdminUser

router = APIRouter(prefix="/admin", tags=["admin"])

ADMIN_ERROR_RESPONSES = {
    401: {"model": ErrorResponse, "description": "Missing or invalid bearer token."},
    403: {"model": ErrorResponse, "description": "Admin role/group required."},
    500: {"model": ErrorResponse, "description": "Unexpected server error."},
}


class AuditEventOut(BaseModel):
    id: int
    action: str
    actorEmail: str
    detail: str
    correlationId: str | None
    createdAt: datetime


@router.get("/audit-events", response_model=list[AuditEventOut], responses=ADMIN_ERROR_RESPONSES)
def list_audit_events(
    _: AdminUser,
    db: Annotated[Session, Depends(get_db)],
    limit: Annotated[int, Query(ge=1, le=200)] = 50,
    action: Annotated[str | None, Query(description="Action prefix, e.g. `chat`.")] = None,
) -> list[AuditEventOut]:
    """Most recent audit events first."""
    query = select(AuditEvent).order_by(AuditEvent.id.desc()).limit(limit)
    if action:
        query = query.where(AuditEvent.action.startswith(action))
    return [
        AuditEventOut(
            id=event.id,
            action=event.action,
            actorEmail=event.actor_email,
            detail=event.detail,
            correlationId=event.correlation_id,
            createdAt=event.created_at,
        )
        for event in db.scalars(query)
    ]
