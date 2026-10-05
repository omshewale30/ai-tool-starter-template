import json

import pytest

from app.core.config import Settings
from app.core.errors import UpstreamServiceError
from app.services.ai.factory import _provider_dependency
from app.services.ai.mock_provider import MockAIProvider
from app.services.search import AISearchRetriever, Passage
from app.services.search.search import _retriever_dependency

PASSAGES = [
    Passage(
        chunk_id="c1",
        source="travel-policy.pdf",
        title="Travel policy",
        text="Per diem is $59.",
        score=2.0,
    ),
    Passage(
        chunk_id="c2", source="pcard.docx", title="", text="P-Card limit is $5,000.", score=1.5
    ),
]


class FakeRetriever:
    def __init__(self, passages=PASSAGES, error=None):
        self.passages, self.error, self.queries = passages, error, []

    async def retrieve(self, query, *, top=5):
        self.queries.append((query, top))
        if self.error:
            raise self.error
        return self.passages


def parse_sse(text):
    events = []
    for block in text.strip().split("\n\n"):
        lines = dict(line.split(": ", 1) for line in block.splitlines())
        events.append((lines["event"], json.loads(lines["data"])))
    return events


def test_grounded_stream_sends_citations_then_the_answer(client):
    retriever = FakeRetriever()
    captured = {}

    class Recording(MockAIProvider):
        async def stream_chat(self, messages, **kwargs):
            captured["system"] = messages[0].content
            async for event in super().stream_chat(messages, **kwargs):
                yield event

    client.app.dependency_overrides[_retriever_dependency] = lambda: retriever
    client.app.dependency_overrides[_provider_dependency] = lambda: Recording()

    resp = client.post("/api/v1/rag/chat/stream", json={"message": "What is the per diem?"})

    assert resp.status_code == 200
    events = parse_sse(resp.text)
    name, citations = events[0]
    assert name == "citations"
    assert citations == [
        {
            "id": 1,
            "title": "Travel policy",
            "source": "travel-policy.pdf",
            "snippet": "Per diem is $59.",
        },
        {
            "id": 2,
            "title": "pcard.docx",
            "source": "pcard.docx",
            "snippet": "P-Card limit is $5,000.",
        },
    ]
    assert events[-1][0] == "done"
    assert retriever.queries == [("What is the per diem?", 5)]
    # The model sees the numbered sources it is told to cite.
    assert "[1] Travel policy\nPer diem is $59." in captured["system"]


def test_search_failure_is_a_502_before_streaming(client):
    client.app.dependency_overrides[_retriever_dependency] = lambda: FakeRetriever(
        error=UpstreamServiceError("Document search failed")
    )
    resp = client.post("/api/v1/rag/chat/stream", json={"message": "anything"})
    assert resp.status_code == 502
    assert resp.json()["error"]["code"] == "upstream_error"


def test_rag_route_is_not_in_the_openapi_document(client):
    from app.main import app

    assert not any(path.startswith("/api/v1/rag") for path in app.openapi()["paths"])


async def test_retriever_runs_a_hybrid_query_and_maps_hits():
    calls = []

    class FakeSearchClient:
        def search(self, **kwargs):
            calls.append(kwargs)
            return [
                {
                    "chunk_id": "c1",
                    "parent_id": "a.pdf",
                    "title": "A",
                    "chunk": "text",
                    "@search.score": 1.2,
                }
            ]

    retriever = AISearchRetriever(Settings(environment="test"), client=FakeSearchClient())
    passages = await retriever.retrieve("per diem", top=3)

    assert passages == [Passage(chunk_id="c1", source="a.pdf", title="A", text="text", score=1.2)]
    request = calls[0]
    assert request["search_text"] == "per diem" and request["top"] == 3
    assert request["vector_queries"][0].as_dict() == {
        "text": "per diem",
        "k": 3,
        "fields": "text_vector",
        "kind": "text",
    }


async def test_retriever_requires_an_endpoint():
    with pytest.raises(UpstreamServiceError):
        await AISearchRetriever(Settings(environment="test")).retrieve("q")


async def test_retriever_normalizes_sdk_errors():
    class Broken:
        def search(self, **kwargs):
            raise RuntimeError("403")

    with pytest.raises(UpstreamServiceError):
        await AISearchRetriever(Settings(environment="test"), client=Broken()).retrieve("q")
