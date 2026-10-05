"""FastAPI application entrypoint.

Wires together: settings, structured logging, correlation-id middleware, CORS,
centralized error handling, health probes, and the versioned API router.
"""
from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.v1.router import api_router
from app.api.v1.routes import health
from app.core.config import get_settings
from app.core.errors import register_error_handlers
from app.core.logging import configure_logging, get_logger
from app.core.middleware import CorrelationIdMiddleware

settings = get_settings()
configure_logging(settings.log_level)
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
    # Optional: enable Azure Monitor OpenTelemetry when configured.
    if settings.applicationinsights_connection_string:
        try:
            from azure.monitor.opentelemetry import configure_azure_monitor

            configure_azure_monitor(
                connection_string=settings.applicationinsights_connection_string
            )
            logger.info("Azure Monitor OpenTelemetry enabled")
        except Exception:  # noqa: BLE001
            logger.exception("Failed to configure Azure Monitor; continuing without it")
    yield


def create_app() -> FastAPI:
    # Interactive docs are for local development only. The API sits behind the
    # web app in Azure; the OpenAPI document is still generated for the
    # frontend's typed client (see scripts/export_openapi.py).
    docs_enabled = settings.environment in {"local", "test"}
    app = FastAPI(
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
