"""Aggregate all /api/v1 routes into a single router."""

from __future__ import annotations

from fastapi import APIRouter

from app.api.v1.routes import admin, chat, me{% if cookiecutter.enable_ai_search == "yes" %}, rag{% endif %}

api_router = APIRouter()
api_router.include_router(me.router)
api_router.include_router(chat.router)
api_router.include_router(admin.router)
{%- if cookiecutter.enable_ai_search == "yes" %}
api_router.include_router(rag.router)
{%- endif %}
