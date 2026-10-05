"""Typed application settings, loaded from environment variables.

All configuration lives here so the rest of the app depends on a single, typed
`Settings` object rather than reading `os.environ` directly.
"""
from __future__ import annotations

from enum import StrEnum
from functools import lru_cache

from pydantic import Field, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

_LOCAL_ONLY_ENVIRONMENTS = {"local", "test"}


class AIProviderName(StrEnum):
    mock = "mock"
    foundry = "foundry"


class AuthMode(StrEnum):
    """`disabled` bypasses JWT validation and is for LOCAL DEV ONLY."""

    disabled = "disabled"
    entra = "entra"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
        case_sensitive=False,
    )

    # ---- Core ----
    app_name: str = "{{ cookiecutter.project_name }}"
    environment: str = "local"
    log_level: str = "INFO"
    api_v1_prefix: str = "/api/v1"

    # ---- CORS ----
    # Empty by default: browsers reach the API through the web app's same-origin
    # /api/* forwarder, so no cross-origin access is needed. Set only if another
    # origin must call the API directly from a browser.
    cors_allow_origins: str = ""

    # ---- AI provider ----
    ai_provider: AIProviderName = AIProviderName.mock

    # ---- Auth ----
    auth_mode: AuthMode = AuthMode.disabled
    azure_tenant_id: str = ""
    entra_backend_client_id: str = ""
    entra_backend_app_id_uri: str = ""
    admin_group_id: str = ""
    # Entra v2 issuer & JWKS are derived from the tenant id.
    jwt_leeway_seconds: int = 60

    # ---- Database ----
    # PostgreSQL in Azure and docker-compose; SQLite for tests. A plain
    # `postgres://` or `postgresql://` URL is accepted and mapped to psycopg.
    database_url: str = "sqlite+pysqlite:///./local.db"

    # ---- Azure AI Foundry (only used when ai_provider == foundry) ----
    azure_ai_foundry_endpoint: str = ""
    azure_ai_foundry_project_name: str = ""
    azure_ai_foundry_deployment_name: str = ""
    azure_ai_foundry_api_version: str = "2024-08-01-preview"

    # ---- Azure Blob Storage ----
    azure_storage_account_url: str = ""
    azure_storage_container: str = "uploads"

    # ---- Azure AI Search (optional) ----
    azure_search_endpoint: str = ""
    azure_search_index: str = "default"

    # ---- Observability ----
    applicationinsights_connection_string: str = Field(
        default="", alias="APPLICATIONINSIGHTS_CONNECTION_STRING"
    )

    @property
    def cors_origins_list(self) -> list[str]:
        return [o.strip() for o in self.cors_allow_origins.split(",") if o.strip()]

    @property
    def entra_issuer(self) -> str:
        return f"https://login.microsoftonline.com/{self.azure_tenant_id}/v2.0"

    @property
    def entra_jwks_uri(self) -> str:
        return f"https://login.microsoftonline.com/{self.azure_tenant_id}/discovery/v2.0/keys"

    @property
    def auth_disabled(self) -> bool:
        return self.auth_mode == AuthMode.disabled

    @field_validator("environment")
    @classmethod
    def _normalize_env(cls, v: str) -> str:
        return v.strip().lower()

    @field_validator("database_url")
    @classmethod
    def _use_psycopg_driver(cls, v: str) -> str:
        for prefix in ("postgres://", "postgresql://"):
            if v.startswith(prefix):
                return "postgresql+psycopg://" + v[len(prefix) :]
        return v

    @model_validator(mode="after")
    def _validate_security_invariants(self) -> Settings:
        if self.auth_mode == AuthMode.disabled and self.environment not in _LOCAL_ONLY_ENVIRONMENTS:
            raise ValueError(
                "AUTH_MODE=disabled is allowed only when ENVIRONMENT is 'local' or 'test'."
            )
        if self.environment not in _LOCAL_ONLY_ENVIRONMENTS and "*" in self.cors_origins_list:
            raise ValueError(
                "CORS_ALLOW_ORIGINS cannot contain '*' outside local/test environments."
            )
        return self


@lru_cache
def get_settings() -> Settings:
    """Cached settings accessor used across the app and as a FastAPI dependency."""
    return Settings()
