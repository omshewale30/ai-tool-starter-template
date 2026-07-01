"""Import all models so they register on `Base.metadata`."""
from app.models.audit_event import AuditEvent

__all__ = ["AuditEvent"]
