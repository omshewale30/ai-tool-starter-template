"""Microsoft Entra ID access-token validation.

Validates the incoming bearer JWT against the tenant issuer, audience, and the
tenant's published signing keys (JWKS). Role/group claims are extracted for
authorization decisions elsewhere.

When `AUTH_MODE=disabled` (local development only) validation is bypassed and a
clearly-labelled fake development principal is returned. This path logs a
warning on every request so it can never be mistaken for a secure configuration.
"""
from __future__ import annotations

from dataclasses import dataclass, field

import jwt
from jwt import PyJWKClient

from app.core.config import Settings
from app.core.errors import UnauthorizedError
from app.core.logging import get_logger

logger = get_logger(__name__)


@dataclass
class Principal:
    """The authenticated caller, normalized from token claims."""

    subject: str
    name: str
    email: str
    roles: list[str] = field(default_factory=list)
    groups: list[str] = field(default_factory=list)
    is_dev_principal: bool = False

    def has_role(self, role: str) -> bool:
        return role in self.roles

    def in_group(self, group_id: str) -> bool:
        return bool(group_id) and group_id in self.groups


# Cache one JWKS client per tenant JWKS URI. PyJWKClient caches keys internally.
_jwks_clients: dict[str, PyJWKClient] = {}


def _jwks_client(jwks_uri: str) -> PyJWKClient:
    client = _jwks_clients.get(jwks_uri)
    if client is None:
        client = PyJWKClient(jwks_uri, cache_keys=True)
        _jwks_clients[jwks_uri] = client
    return client


def _dev_principal() -> Principal:
    logger.warning(
        "AUTH_MODE=disabled: returning a FAKE development principal. "
        "This is UNSAFE and must never be used outside local development."
    )
    return Principal(
        subject="dev-user",
        name="Local Developer",
        email="dev@localhost",
        roles=["user", "admin"],
        groups=["local-dev-admins"],
        is_dev_principal=True,
    )


def _extract_principal(claims: dict) -> Principal:
    # Entra puts app roles in `roles` and (when configured) group ids in `groups`.
    roles = claims.get("roles") or []
    groups = claims.get("groups") or []
    return Principal(
        subject=claims.get("oid") or claims.get("sub") or "unknown",
        name=claims.get("name", ""),
        email=claims.get("preferred_username") or claims.get("upn") or claims.get("email", ""),
        roles=list(roles),
        groups=list(groups),
    )


def validate_token(token: str, settings: Settings) -> Principal:
    """Validate a bearer token and return the caller principal.

    Raises `UnauthorizedError` on any validation failure.
    """
    if settings.auth_disabled:
        return _dev_principal()

    if not settings.azure_tenant_id:
        raise UnauthorizedError("Auth is enabled but AZURE_TENANT_ID is not configured")

    # The accepted audience can be the API's app id URI or its client id.
    audiences = [
        a
        for a in (settings.entra_backend_app_id_uri, settings.entra_backend_client_id)
        if a
    ]

    try:
        signing_key = _jwks_client(settings.entra_jwks_uri).get_signing_key_from_jwt(token)
        claims = jwt.decode(
            token,
            signing_key.key,
            algorithms=["RS256"],
            audience=audiences or None,
            issuer=settings.entra_issuer,
            leeway=settings.jwt_leeway_seconds,
            options={"require": ["exp", "iss", "aud"]},
        )
    except jwt.PyJWTError as exc:
        logger.info("Token validation failed: %s", exc)
        raise UnauthorizedError("Invalid or expired access token") from exc

    return _extract_principal(claims)
