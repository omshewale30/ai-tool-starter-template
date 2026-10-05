"""Provider behaviour without network access: mock, structured output, and the Azure
OpenAI provider against a fake SDK client."""

from types import SimpleNamespace

import pytest
from pydantic import BaseModel

from app.core.config import Settings
from app.core.errors import UpstreamServiceError
from app.prompts import load_prompt, render_prompt
from app.services.ai.base import ChatMessage
from app.services.ai.foundry_provider import AzureFoundryProvider
from app.services.ai.mock_provider import MockAIProvider

USER = [ChatMessage(role="user", content="hi")]


class Invoice(BaseModel):
    vendor: str
    total: float


async def test_mock_embeddings_are_stable_and_distinct():
    mock = MockAIProvider()
    first, second, again = await mock.embed(["a", "b", "a"])
    assert first == again
    assert first != second
    assert len(first) == 16


async def test_complete_json_returns_a_validated_model():
    MockAIProvider.json_responses.append('{"vendor": "Acme", "total": 12.5}')
    invoice = await MockAIProvider().complete_json(USER, Invoice)
    assert invoice == Invoice(vendor="Acme", total=12.5)


async def test_complete_json_rejects_a_reply_that_does_not_match():
    MockAIProvider.json_responses.append('{"vendor": "Acme"}')
    with pytest.raises(UpstreamServiceError):
        await MockAIProvider().complete_json(USER, Invoice)


def test_prompts_load_from_files():
    assert "Finance and Operations" in load_prompt("assistant")
    assert "Budget Tool" in render_prompt("assistant", app_name="Budget Tool")


# ---- Azure OpenAI provider, against a fake client -------------------------------

SETTINGS = Settings(
    environment="test",
    azure_ai_foundry_endpoint="https://example.openai.azure.com",
    azure_ai_foundry_deployment_name="gpt-test",
    azure_ai_foundry_embedding_deployment_name="embed-test",
)


class FakeCompletions:
    def __init__(self, result=None, error=None):
        self.result, self.error, self.calls = result, error, []

    async def create(self, **kwargs):
        self.calls.append(kwargs)
        if self.error:
            raise self.error
        return self.result


def fake_client(completions=None, embeddings=None):
    return SimpleNamespace(chat=SimpleNamespace(completions=completions), embeddings=embeddings)


def completion(text="hello", finish="stop"):
    return SimpleNamespace(
        model="gpt-test-2026",
        choices=[SimpleNamespace(message=SimpleNamespace(content=text), finish_reason=finish)],
        usage=SimpleNamespace(prompt_tokens=7, completion_tokens=3),
    )


def test_provider_requires_endpoint_and_deployment():
    with pytest.raises(UpstreamServiceError):
        AzureFoundryProvider(Settings(environment="test"))


async def test_chat_maps_the_response_and_omits_unset_knobs():
    completions = FakeCompletions(result=completion())
    provider = AzureFoundryProvider(SETTINGS, client=fake_client(completions))

    result = await provider.chat(USER)

    assert (result.content, result.model, result.finish_reason) == (
        "hello",
        "gpt-test-2026",
        "stop",
    )
    assert (
        result.usage.prompt_tokens,
        result.usage.completion_tokens,
        result.usage.total_tokens,
    ) == (7, 3, 10)
    request = completions.calls[0]
    assert request["model"] == "gpt-test"
    # Reasoning models reject temperature; nothing is sent unless asked for.
    assert "temperature" not in request and "max_completion_tokens" not in request


async def test_chat_json_mode_and_limits_are_forwarded():
    completions = FakeCompletions(result=completion('{"vendor": "A", "total": 1}'))
    provider = AzureFoundryProvider(SETTINGS, client=fake_client(completions))

    invoice = await provider.complete_json(USER, Invoice)

    assert invoice.vendor == "A"
    request = completions.calls[0]
    assert request["response_format"] == {"type": "json_object"}
    assert request["temperature"] == 0.0


async def test_sdk_errors_become_upstream_errors():
    provider = AzureFoundryProvider(
        SETTINGS, client=fake_client(FakeCompletions(error=RuntimeError("429")))
    )
    with pytest.raises(UpstreamServiceError):
        await provider.chat(USER)


async def test_stream_yields_text_then_done_with_usage():
    async def chunks():
        def chunk(text=None, finish=None, usage=None, choices=True):
            choice = SimpleNamespace(delta=SimpleNamespace(content=text), finish_reason=finish)
            return SimpleNamespace(
                model="gpt-test-2026", choices=[choice] if choices else [], usage=usage
            )

        yield chunk("Hel")
        yield chunk("lo", finish="stop")
        # With include_usage, the final chunk has no choices and carries the usage.
        yield chunk(choices=False, usage=SimpleNamespace(prompt_tokens=4, completion_tokens=2))

    completions = FakeCompletions(result=chunks())
    provider = AzureFoundryProvider(SETTINGS, client=fake_client(completions))

    events = [event async for event in provider.stream_chat(USER)]

    assert [e.text for e in events if e.type == "delta"] == ["Hel", "lo"]
    done = events[-1]
    assert (done.type, done.model, done.finish_reason) == ("done", "gpt-test-2026", "stop")
    assert (done.usage.prompt_tokens, done.usage.completion_tokens) == (4, 2)
    assert completions.calls[0]["stream_options"] == {"include_usage": True}


async def test_embeddings_keep_input_order():
    class FakeEmbeddings:
        async def create(self, **kwargs):
            assert kwargs["model"] == "embed-test"
            return SimpleNamespace(
                data=[
                    SimpleNamespace(index=1, embedding=[1.0]),
                    SimpleNamespace(index=0, embedding=[0.0]),
                ]
            )

    provider = AzureFoundryProvider(SETTINGS, client=fake_client(embeddings=FakeEmbeddings()))
    assert await provider.embed(["first", "second"]) == [[0.0], [1.0]]
