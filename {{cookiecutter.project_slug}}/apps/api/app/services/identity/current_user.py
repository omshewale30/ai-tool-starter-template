"""FastAPI dependencies for authentication and authorization.

Usage in routes:

    @router.get("/me")
    def me(user: Principal = Depends(get_current_user)): ...

    @router.get("/admin/example")
    def admin(user: Principal = Depends(require_admin)): ...
"""
from __future__ import annotations

from typing import Annotated

from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.core.config import Settings, get_settings
from app.core.errors import ForbiddenError, UnauthorizedError
from app.core.security import Principal, validate_token

# auto_error=False so we can raise our own consistent error envelope.
_bearer = HTTPBearer(auto_error=False)


def get_current_user(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> Principal:
    """Resolve and validate the caller. Raises 401 if not authenticated."""
    if settings.auth_disabled:
        # Development bypass; validate_token returns the fake dev principal.
        return validate_token("", settings)

    if credentials is None or not credentials.credentials:
        raise UnauthorizedError("Missing bearer token")

    return validate_token(credentials.credentials, settings)


def require_admin(
    user: Annotated[Principal, Depends(get_current_user)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> Principal:
    """Authorize admin-only routes via app role or configured admin group."""
    if user.has_role("admin") or user.in_group(settings.admin_group_id):
        return user
    raise ForbiddenError("Admin role or group membership required")


CurrentUser = Annotated[Principal, Depends(get_current_user)]
AdminUser = Annotated[Principal, Depends(require_admin)]
