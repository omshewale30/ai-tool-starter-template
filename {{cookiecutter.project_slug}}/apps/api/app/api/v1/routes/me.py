"""/api/v1/me — returns the authenticated caller's profile from token claims."""
from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends

from app.core.config import Settings, get_settings
from app.schemas.common import ErrorResponse
from app.schemas.user import MeResponse
from app.services.identity.current_user import CurrentUser

router = APIRouter(tags=["me"])

ME_ERROR_RESPONSES = {
    401: {"model": ErrorResponse, "description": "Missing or invalid bearer token."},
    500: {"model": ErrorResponse, "description": "Unexpected server error."},
}

@router.get("/me", response_model=MeResponse, responses=ME_ERROR_RESPONSES)
def me(user: CurrentUser, settings: Annotated[Settings, Depends(get_settings)]) -> MeResponse:
    is_admin = user.has_role("admin") or user.in_group(settings.admin_group_id)
    return MeResponse(
        subject=user.subject,
        name=user.name,
        email=user.email,
        roles=user.roles,
        groups=user.groups,
        isAdmin=is_admin,
        isDevPrincipal=user.is_dev_principal,
    )
