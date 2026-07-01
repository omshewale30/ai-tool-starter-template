"""/api/v1/admin/* — routes gated by admin role/group membership."""
from __future__ import annotations

from fastapi import APIRouter
from pydantic import BaseModel

from app.schemas.common import ErrorResponse
from app.services.identity.current_user import AdminUser

router = APIRouter(prefix="/admin", tags=["admin"])


class AdminExampleResponse(BaseModel):
    message: str
    actor: str


ADMIN_ERROR_RESPONSES = {
    401: {"model": ErrorResponse, "description": "Missing or invalid bearer token."},
    403: {"model": ErrorResponse, "description": "Admin role/group required."},
    500: {"model": ErrorResponse, "description": "Unexpected server error."},
}


@router.get("/example", response_model=AdminExampleResponse, responses=ADMIN_ERROR_RESPONSES)
def admin_example(user: AdminUser) -> AdminExampleResponse:
    """Trivial admin-only endpoint proving the authorization check works."""
    return AdminExampleResponse(
        message="You have admin access.",
        actor=user.email or user.subject,
    )
