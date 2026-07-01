"""Select the AI provider based on configuration.

Cached per-settings so we don't rebuild clients on every request. The chat route
depends on `get_ai_provider` and never imports a concrete provider directly.
"""
from __future__ import annotations

from functools import lru_cache

from app.core.config import AIProviderName, Settings, get_settings
from app.services.ai.base import AIProvider
from app.services.ai.mock_provider import MockAIProvider


@lru_cache
def _build_provider(provider_name: AIProviderName) -> AIProvider:
    if provider_name == AIProviderName.foundry:
        # Imported here so the mock path never imports Foundry/Azure deps.
        from app.services.ai.foundry_provider import AzureFoundryProvider

        return AzureFoundryProvider(get_settings())
    return MockAIProvider()


def get_ai_provider(settings: Settings | None = None) -> AIProvider:
    settings = settings or get_settings()
    return _build_provider(settings.ai_provider)
