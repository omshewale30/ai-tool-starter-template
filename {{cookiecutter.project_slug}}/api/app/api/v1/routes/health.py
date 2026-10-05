"""Health endpoints (unauthenticated).

- /health/live  : process is up. Container Apps liveness probe.
- /health/ready : the database is reachable. Container Apps readiness probe.
- /api/health   : deployment health report. The web app forwards `/api/*` here,
                  so one request proves browser -> web -> API -> database. The
                  publish smoke test and `scripts/cd.sh` assert on its body.

`/api/health` always answers 200 and reports booleans only, never configuration
values; callers decide what "healthy enough" means from the body.
"""
from __future__ import annotations

from typing import Annotated, Literal

from fastapi import APIRouter, Depends, Response
from pydantic import BaseModel
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.core.config import AIProviderName, Settings, get_settings
from app.core.logging import get_logger
from app.db.session import get_db
from app.schemas.common import HealthResponse

logger = get_logger(__name__)

router = APIRouter(prefix="/health", tags=["health"])
api_health_router = APIRouter(tags=["health"])


@router.get("/live", response_model=HealthResponse)
def live() -> HealthResponse:
    return HealthResponse(status="ok")


@router.get("/ready", response_model=HealthResponse)
def ready(db: Annotated[Session, Depends(get_db)]) -> HealthResponse:
    # A trivial query confirms the DB connection is usable.
    db.execute(text("SELECT 1"))
    return HealthResponse(status="ok")


class AuthHealth(BaseModel):
    mode: str
    configured: bool


class AIHealth(BaseModel):
    provider: str
    configured: bool


class DeploymentHealth(BaseModel):
    status: Literal["ok", "degraded"]
    environment: str
    database: Literal["ok", "error"]
    auth: AuthHealth
    ai: AIHealth


def _auth_configured(settings: Settings) -> bool:
    if settings.auth_disabled:
        return False
    return bool(
        settings.azure_tenant_id
        and (settings.entra_backend_client_id or settings.entra_backend_app_id_uri)
    )


def _ai_configured(settings: Settings) -> bool:
    if settings.ai_provider == AIProviderName.mock:
        return True
    return bool(settings.azure_ai_foundry_endpoint and settings.azure_ai_foundry_deployment_name)


def _database_ok(db: Session) -> bool:
    try:
        db.execute(text("SELECT 1"))
    except Exception:  # noqa: BLE001 — reported in the body, details only in logs
        logger.exception("Health check database query failed")
        db.rollback()
        return False
    return True


@api_health_router.get("/api/health", response_model=DeploymentHealth)
def deployment_health(
    response: Response,
    db: Annotated[Session, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> DeploymentHealth:
    response.headers["Cache-Control"] = "no-store"
    database_ok = _database_ok(db)
    auth_ok = settings.auth_disabled or _auth_configured(settings)
    ai_ok = _ai_configured(settings)
    return DeploymentHealth(
        status="ok" if database_ok and auth_ok and ai_ok else "degraded",
        environment=settings.environment,
        database="ok" if database_ok else "error",
        auth=AuthHealth(mode=settings.auth_mode.value, configured=_auth_configured(settings)),
        ai=AIHealth(provider=settings.ai_provider.value, configured=ai_ok),
    )
