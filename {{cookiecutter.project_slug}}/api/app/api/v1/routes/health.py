"""Liveness and readiness probes (unauthenticated).

- /health/live  : process is up.
- /health/ready : dependencies (DB) are reachable.
Container Apps / K8s use these for health checks.
"""
from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.schemas.common import HealthResponse

router = APIRouter(prefix="/health", tags=["health"])


@router.get("/live", response_model=HealthResponse)
def live() -> HealthResponse:
    return HealthResponse(status="ok")


@router.get("/ready", response_model=HealthResponse)
def ready(db: Annotated[Session, Depends(get_db)]) -> HealthResponse:
    # A trivial query confirms the DB connection is usable.
    db.execute(text("SELECT 1"))
    return HealthResponse(status="ok")
