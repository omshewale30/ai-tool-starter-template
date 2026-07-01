"""Auth utility tests that need no network / signing keys."""
import pytest
from pydantic import ValidationError

from app.core.config import AuthMode, Settings
from app.core.errors import ForbiddenError, UnauthorizedError
from app.core.security import Principal, _extract_principal, validate_token
from app.services.identity.current_user import require_admin


def test_disabled_mode_returns_dev_admin_principal():
    settings = Settings(auth_mode=AuthMode.disabled)
    principal = validate_token("", settings)
    assert principal.is_dev_principal is True
    assert principal.has_role("admin")


def test_extract_principal_maps_claims():
    principal = _extract_principal(
        {
            "oid": "abc-123",
            "name": "Ada Lovelace",
            "preferred_username": "ada@contoso.com",
            "roles": ["user", "admin"],
            "groups": ["group-1"],
        }
    )
    assert principal.subject == "abc-123"
    assert principal.email == "ada@contoso.com"
    assert principal.has_role("admin")
    assert principal.in_group("group-1")
    assert not principal.in_group("nope")


def test_enabled_mode_without_tenant_is_unauthorized():
    settings = Settings(auth_mode=AuthMode.entra, azure_tenant_id="")
    with pytest.raises(UnauthorizedError):
        validate_token("some.jwt.token", settings)


def test_disabled_mode_rejected_outside_local_or_test_env():
    with pytest.raises(ValidationError):
        Settings(auth_mode=AuthMode.disabled, environment="prod")


def test_wildcard_cors_rejected_outside_local_or_test_env():
    with pytest.raises(ValidationError):
        Settings(auth_mode=AuthMode.entra, environment="prod", cors_allow_origins="*")


def test_require_admin_rejects_non_admin():
    non_admin = Principal(subject="u1", name="U", email="u@x", roles=["user"], groups=[])
    settings = Settings(admin_group_id="admins")
    with pytest.raises(ForbiddenError):
        require_admin(non_admin, settings)


def test_require_admin_allows_group_member():
    member = Principal(subject="u2", name="U2", email="u2@x", roles=[], groups=["admins"])
    settings = Settings(admin_group_id="admins")
    assert require_admin(member, settings) is member
