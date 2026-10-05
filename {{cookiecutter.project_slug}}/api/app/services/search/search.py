"""Azure AI Search wrapper (optional, keyless / managed identity).

Provided as a scaffold for RAG-style retrieval. Enabled only when
`AZURE_SEARCH_ENDPOINT` is set. Install the extra to use it:

    pip install -e ".[search]"
"""
from __future__ import annotations

from dataclasses import dataclass

from app.core.config import Settings
from app.core.errors import UpstreamServiceError
from app.core.logging import get_logger

logger = get_logger(__name__)


@dataclass
class SearchHit:
    id: str
    score: float
    content: str


class AISearchService:
    def __init__(self, settings: Settings):
        self._settings = settings
        self._client = None

    @property
    def enabled(self) -> bool:
        return bool(self._settings.azure_search_endpoint)

    def _get_client(self):
        if not self.enabled:
            raise UpstreamServiceError("Azure AI Search is not configured (AZURE_SEARCH_ENDPOINT)")
        if self._client is None:
            from azure.identity import DefaultAzureCredential
            from azure.search.documents import SearchClient

            self._client = SearchClient(
                endpoint=self._settings.azure_search_endpoint,
                index_name=self._settings.azure_search_index,
                credential=DefaultAzureCredential(),
            )
        return self._client

    def query(self, text: str, *, top: int = 5) -> list[SearchHit]:
        client = self._get_client()
        results = client.search(search_text=text, top=top)
        hits: list[SearchHit] = []
        for r in results:
            hits.append(
                SearchHit(
                    id=str(r.get("id", "")),
                    score=float(r.get("@search.score", 0.0)),
                    content=str(r.get("content", "")),
                )
            )
        return hits
