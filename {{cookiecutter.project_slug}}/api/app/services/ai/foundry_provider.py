"""Azure OpenAI / AI Foundry provider: the one place the app talks to the models.

Authentication is keyless: DefaultAzureCredential resolves the container app's
user-assigned managed identity in Azure (AZURE_CLIENT_ID) and your `az login`
locally, and exchanges it for a Cognitive Services token. UNC grants the identity
"Cognitive Services OpenAI User" on the resource (docs/ai.md). No API keys exist.

The OpenAI SDK handles retries with backoff for 429 and 5xx responses
(AI_MAX_RETRIES) and enforces AI_REQUEST_TIMEOUT_SECONDS per request. Every SDK
error is normalized to `UpstreamServiceError` (502) so callers see one failure
type and clients get the standard error envelope.
"""

from __future__ import annotations

from collections.abc import AsyncIterator
from typing import Any

from app.core.config import Settings
from app.core.errors import UpstreamServiceError
from app.core.logging import get_logger
from app.services.ai.base import AIProvider, ChatMessage, ChatResult, StreamEvent, Usage

logger = get_logger(__name__)

# Token audience for Azure OpenAI / Cognitive Services.
_AZURE_AI_SCOPE = "https://cognitiveservices.azure.com/.default"


def _usage(raw: Any) -> Usage:
    if raw is None:
        return Usage()
    return Usage(
        prompt_tokens=getattr(raw, "prompt_tokens", None),
        completion_tokens=getattr(raw, "completion_tokens", None),
    )


class AzureFoundryProvider(AIProvider):
    name = "foundry"

    def __init__(self, settings: Settings, client: Any | None = None):
        """`client` is injectable for tests; by default it is built lazily on first use."""
        if not settings.azure_ai_foundry_endpoint or not settings.azure_ai_foundry_deployment_name:
            raise UpstreamServiceError(
                "AZURE_AI_FOUNDRY_ENDPOINT and AZURE_AI_FOUNDRY_DEPLOYMENT_NAME must be set"
            )
        self._settings = settings
        self._client = client

    def _get_client(self) -> Any:
        if self._client is None:
            from azure.identity import DefaultAzureCredential, get_bearer_token_provider
            from openai import AsyncAzureOpenAI

            self._client = AsyncAzureOpenAI(
                azure_endpoint=self._settings.azure_ai_foundry_endpoint,
                api_version=self._settings.azure_ai_foundry_api_version,
                azure_ad_token_provider=get_bearer_token_provider(
                    DefaultAzureCredential(), _AZURE_AI_SCOPE
                ),
                timeout=self._settings.ai_request_timeout_seconds,
                max_retries=self._settings.ai_max_retries,
            )
        return self._client

    def _request(
        self, messages: list[ChatMessage], temperature: float | None, max_tokens: int | None
    ) -> dict[str, Any]:
        """Arguments shared by chat and stream_chat. Unset knobs are omitted, not
        sent as defaults: some models (reasoning models) reject `temperature`."""
        request: dict[str, Any] = {
            "model": self._settings.azure_ai_foundry_deployment_name,
            "messages": [{"role": m.role, "content": m.content} for m in messages],
        }
        if temperature is not None:
            request["temperature"] = temperature
        limit = max_tokens or self._settings.ai_max_output_tokens
        if limit is not None:
            request["max_completion_tokens"] = limit
        return request

    async def chat(
        self,
        messages: list[ChatMessage],
        *,
        temperature: float | None = None,
        max_tokens: int | None = None,
        json_mode: bool = False,
    ) -> ChatResult:
        request = self._request(messages, temperature, max_tokens)
        if json_mode:
            request["response_format"] = {"type": "json_object"}
        try:
            completion = await self._get_client().chat.completions.create(**request)
        except Exception as exc:  # noqa: BLE001 — normalize every SDK/transport error
            logger.exception("Azure OpenAI chat request failed")
            raise UpstreamServiceError("AI service request failed") from exc

        choice = completion.choices[0]
        return ChatResult(
            content=choice.message.content or "",
            model=completion.model,
            usage=_usage(getattr(completion, "usage", None)),
            finish_reason=choice.finish_reason,
        )

    async def stream_chat(
        self,
        messages: list[ChatMessage],
        *,
        temperature: float | None = None,
        max_tokens: int | None = None,
    ) -> AsyncIterator[StreamEvent]:
        request = self._request(messages, temperature, max_tokens)
        # Without include_usage a streamed response reports no token counts.
        request.update(stream=True, stream_options={"include_usage": True})

        model: str | None = None
        finish_reason: str | None = None
        usage = Usage()
        try:
            stream = await self._get_client().chat.completions.create(**request)
            async for chunk in stream:
                model = getattr(chunk, "model", None) or model
                if getattr(chunk, "usage", None) is not None:
                    usage = _usage(chunk.usage)
                for choice in chunk.choices or []:
                    if choice.finish_reason:
                        finish_reason = choice.finish_reason
                    text = getattr(choice.delta, "content", None)
                    if text:
                        yield StreamEvent(type="delta", text=text)
        except Exception as exc:  # noqa: BLE001 — normalize every SDK/transport error
            logger.exception("Azure OpenAI streaming request failed")
            raise UpstreamServiceError("AI service request failed") from exc

        yield StreamEvent(type="done", model=model, usage=usage, finish_reason=finish_reason)

    async def embed(self, texts: list[str]) -> list[list[float]]:
        deployment = self._settings.azure_ai_foundry_embedding_deployment_name
        if not deployment:
            raise UpstreamServiceError("AZURE_AI_FOUNDRY_EMBEDDING_DEPLOYMENT_NAME is not set")
        try:
            response = await self._get_client().embeddings.create(model=deployment, input=texts)
        except Exception as exc:  # noqa: BLE001
            logger.exception("Azure OpenAI embeddings request failed")
            raise UpstreamServiceError("AI service request failed") from exc
        return [item.embedding for item in sorted(response.data, key=lambda item: item.index)]
