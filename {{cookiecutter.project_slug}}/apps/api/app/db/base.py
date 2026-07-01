"""SQLAlchemy declarative base.

`Base` holds the shared metadata. Models import `Base` from here. To make sure
every table is registered before `create_all` / Alembic autogenerate, import
`app.models` (its `__init__` imports all models) rather than this module alone.
"""
from __future__ import annotations

from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    pass
