"""User/profile schemas returned by /api/v1/me."""
from __future__ import annotations

from pydantic import BaseModel


class MeResponse(BaseModel):
    subject: str
    name: str
    email: str
    roles: list[str]
    groups: list[str]
    isAdmin: bool
    # True when auth is disabled locally — surfaced so the UI can warn.
    isDevPrincipal: bool = False
