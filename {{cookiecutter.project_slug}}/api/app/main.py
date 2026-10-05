"""FastAPI application entrypoint.

Wires together: settings, structured logging, correlation-id middleware, CORS,
centralized error handling, health probes, and the versioned API router.
"""
from __future__ import annotations

from contextlib import asynccontextmanager

import fastapi
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.v1.router import api_router
from app.api.v1.routes import health
from app.core.config import get_settings
from app.core.errors import register_error_handlers
from app.core.logging import configure_logging, get_logger
from app.core.middleware import CorrelationIdMiddleware
from app.services.telemetry import configure_telemetry

settings = get_settings()
configure_logging(settings.log_level)
# Before create_app(): the FastAPI instrumentation patches the class it constructs.
configure_telemetry(settings)
logger = get_logger("app.main")


@asynccontextmanager
async def lifespan(_: FastAPI):
    logger.info(
        "Starting %s",
        settings.app_name,
        extra={
            "environment": settings.environment,
            "ai_provider": settings.ai_provider.value,
            "auth_mode": settings.auth_mode.value,
        },
    )
    if settings.auth_disabled:
        logger.warning(
            "AUTH_MODE=disabled — authentication is BYPASSED. "
            "Use only for local development."
        )
    yield


def create_app() -> FastAPI:
    # Interactive docs are for local development only. The API sits behind the
    # web app in Azure; the OpenAPI document is still generated for the
    # frontend's typed client (see scripts/export_openapi.py).
    docs_enabled = settings.environment in {"local", "test"}
    # `fastapi.FastAPI`, looked up now: telemetry instrumentation replaces that class,
    # and the name imported at the top of this module would still be the original.
    app = fastapi.FastAPI(
        title=settings.app_name,
        version="0.1.0",
        description="{{ cookiecutter.project_description }}",
        lifespan=lifespan,
        docs_url="/docs" if docs_enabled else None,
        redoc_url=None,
        openapi_url="/openapi.json" if docs_enabled else None,
    )

    app.add_middleware(CorrelationIdMiddleware)
    if settings.cors_origins_list:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.cors_origins_list,
            allow_credentials=True,
            allow_methods=["*"],
            allow_headers=["*"],
            expose_headers=["X-Correlation-ID"],
        )

    register_error_handlers(app)

    # Health probes at the root; versioned API under /api/v1.
    app.include_router(health.router)
    app.include_router(health.api_health_router)
    app.include_router(api_router, prefix=settings.api_v1_prefix)

    return app


app = create_app()
