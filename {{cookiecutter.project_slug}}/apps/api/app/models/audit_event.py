"""Example domain model: an append-only audit trail of important events."""
from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy import DateTime, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


def _utcnow() -> datetime:
    return datetime.now(UTC)


class AuditEvent(Base):
    __tablename__ = "audit_events"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    # Short machine-readable action, e.g. "chat.completed", "admin.viewed".
    action: Mapped[str] = mapped_column(String(128), index=True)
    # Subject (oid) of the principal that triggered the event.
    actor_subject: Mapped[str] = mapped_column(String(128), index=True)
    actor_email: Mapped[str] = mapped_column(String(256), default="")
    # Optional JSON-ish detail payload (kept as text to stay DB-agnostic).
    detail: Mapped[str] = mapped_column(Text, default="")
    correlation_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utcnow)
