"""Retrieval from Azure AI Search for retrieval-augmented generation (RAG).

The index is built by the search service itself (infra/scripts/setup-search-index.sh):
a Blob indexer reads documents from the `documents` container, a skillset splits
them into chunks and embeds each with UNC's Azure OpenAI embedding deployment, and
the index's vectorizer embeds queries the same way. So this service only queries:
one hybrid request (keyword + vector) with no embedding call of its own.

Keyless: DefaultAzureCredential (the container app's managed identity), which holds
"Search Index Data Reader" on the service (infra/bicep/modules/search.bicep).
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Annotated, Any, Protocol

from fastapi import Depends
from starlette.concurrency import run_in_threadpool

from app.core.config import Settings, get_settings
from app.core.errors import UpstreamServiceError
from app.core.logging import get_logger

logger = get_logger(__name__)

# Index field names, as defined in infra/search/index.json.
_SELECT = ["chunk_id", "parent_id", "title", "chunk"]
_VECTOR_FIELD = "text_vector"


@dataclass
class Passage:
    chunk_id: str
    source: str
    title: str
    text: str
    score: float


class Retriever(Protocol):
    async def retrieve(self, query: str, *, top: int = 5) -> list[Passage]: ...


class AISearchRetriever:
    def __init__(self, settings: Settings, client: Any | None = None):
        """`client` is injectable for tests; by default it is built lazily on first use."""
        self._settings = settings
        self._client = client

    def _get_client(self) -> Any:
        if self._client is None:
            if not self._settings.azure_search_endpoint:
                raise UpstreamServiceError(
                    "Azure AI Search is not configured (AZURE_SEARCH_ENDPOINT)"
                )
            from azure.identity import DefaultAzureCredential
            from azure.search.documents import SearchClient

            self._client = SearchClient(
                endpoint=self._settings.azure_search_endpoint,
                index_name=self._settings.azure_search_index,
                credential=DefaultAzureCredential(),
            )
        return self._client

    def _search(self, query: str, top: int) -> list[Passage]:
        from azure.search.documents.models import VectorizableTextQuery

        results = self._get_client().search(
            search_text=query,
            vector_queries=[
                VectorizableTextQuery(text=query, k_nearest_neighbors=top, fields=_VECTOR_FIELD)
            ],
            select=_SELECT,
            top=top,
        )
        return [
            Passage(
                chunk_id=str(hit.get("chunk_id", "")),
                source=str(hit.get("parent_id", "")),
                title=str(hit.get("title", "")),
                text=str(hit.get("chunk", "")),
                score=float(hit.get("@search.score", 0.0)),
            )
            for hit in results
        ]

    async def retrieve(self, query: str, *, top: int = 5) -> list[Passage]:
        try:
            # The SDK is synchronous; keep it off the event loop.
            return await run_in_threadpool(self._search, query, top)
        except UpstreamServiceError:
            raise
        except Exception as exc:  # noqa: BLE001 — normalize SDK/transport errors
            logger.exception("Azure AI Search query failed")
            raise UpstreamServiceError("Document search failed") from exc


_retriever: AISearchRetriever | None = None


def _retriever_dependency(settings: Annotated[Settings, Depends(get_settings)]) -> Retriever:
    global _retriever
    if _retriever is None:
        _retriever = AISearchRetriever(settings)
    return _retriever


# Use in routes: `async def handler(search: SearchDep): ...`.
# Tests override `_retriever_dependency`.
SearchDep = Annotated[Retriever, Depends(_retriever_dependency)]
