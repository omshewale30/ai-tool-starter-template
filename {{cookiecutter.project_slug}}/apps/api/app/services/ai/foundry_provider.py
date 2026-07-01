"""Azure AI Foundry provider (scaffold).

This is the single place where the app talks to Azure AI Foundry. The actual SDK
call is isolated in `_invoke_model` so you can adapt it to whatever
`azure-ai-*` / `openai` package version you deploy against without touching the
rest of the codebase.

Authentication uses the DefaultAzureCredential chain (managed identity in Azure,
`az login` / environment locally) — no API keys are stored. See `docs/security.md`.

Config (from `Settings`, i.e. environment variables):
  - AZURE_AI_FOUNDRY_ENDPOINT
  - AZURE_AI_FOUNDRY_PROJECT_NAME
  - AZURE_AI_FOUNDRY_DEPLOYMENT_NAME
  - AZURE_AI_FOUNDRY_API_VERSION

Install the SDK extra before enabling this provider:
  pip install -e ".[foundry]"
"""
from __future__ import annotations

from app.core.config import Settings
from app.core.errors import UpstreamServiceError
from app.core.logging import get_logger
from app.services.ai.base import AIProvider, ChatMessage, ChatResult

logger = get_logger(__name__)

# Scope for Azure Cognitive Services / AI Foundry token exchange.
_AZURE_AI_SCOPE = "https://cognitiveservices.azure.com/.default"


class AzureFoundryProvider(AIProvider):
    name = "foundry"

    def __init__(self, settings: Settings):
        if not settings.azure_ai_foundry_endpoint:
            raise UpstreamServiceError("AZURE_AI_FOUNDRY_ENDPOINT is not configured")
        self._settings = settings
        self._client = None  # created lazily on first use

    def _get_client(self):
        """Build the Azure OpenAI-compatible client using keyless (AAD) auth.

        NOTE: Confirm this matches your installed `openai` package version.
        Foundry deployments expose an Azure OpenAI-compatible endpoint; if your
        project uses the `azure-ai-projects` / `azure-ai-inference` SDK instead,
        swap the client construction here and the call in `_invoke_model`.
        """
        if self._client is not None:
            return self._client

        # Imported lazily so the mock path needs neither package nor credentials.
        from azure.identity import DefaultAzureCredential, get_bearer_token_provider
        from openai import AsyncAzureOpenAI

        token_provider = get_bearer_token_provider(
            DefaultAzureCredential(), _AZURE_AI_SCOPE
        )
        self._client = AsyncAzureOpenAI(
            azure_endpoint=self._settings.azure_ai_foundry_endpoint,
            azure_ad_token_provider=token_provider,
            api_version=self._settings.azure_ai_foundry_api_version,
        )
        return self._client

    async def _invoke_model(
        self,
        messages: list[ChatMessage],
        *,
        temperature: float,
        max_tokens: int | None,
    ) -> ChatResult:
        """The one adapter method to update if the SDK surface changes."""
        client = self._get_client()
        completion = await client.chat.completions.create(
            model=self._settings.azure_ai_foundry_deployment_name,
            messages=[{"role": m.role, "content": m.content} for m in messages],
            temperature=temperature,
            max_tokens=max_tokens,
        )
        choice = completion.choices[0]
        usage = getattr(completion, "usage", None)
        return ChatResult(
            content=choice.message.content or "",
            model=completion.model,
            metadata={
                "provider": self.name,
                "finish_reason": choice.finish_reason,
                "total_tokens": getattr(usage, "total_tokens", None),
            },
        )

    async def chat(
        self,
        messages: list[ChatMessage],
        *,
        temperature: float = 0.2,
        max_tokens: int | None = None,
    ) -> ChatResult:
        try:
            return await self._invoke_model(
                messages, temperature=temperature, max_tokens=max_tokens
            )
        except UpstreamServiceError:
            raise
        except Exception as exc:  # noqa: BLE001 — normalize all SDK errors
            logger.exception("Azure AI Foundry call failed")
            raise UpstreamServiceError("AI service request failed") from exc
