"""/api/v1/rag — answers grounded in the indexed documents, with citations.

Streams the same server-sent events as /chat/stream, preceded by one `citations`
event listing the passages the answer may cite as [n]:

    event: citations  data: [{"id": 1, "title": "...", "source": "...", "snippet": "..."}]

Kept out of the OpenAPI document so the committed web types (web/src/lib/api/schema.ts)
are the same whether or not a project enables AI Search; the web reads this stream
with its own small types (web/src/lib/api/sse.ts and ChatPanel).
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends
from fastapi.responses import StreamingResponse

from app.api.v1.routes.chat import conversation
from app.core.config import Settings, get_settings
from app.db.session import SessionFactory
from app.prompts import render_prompt
from app.schemas.chat import ChatRequest
from app.services.ai.factory import AI
from app.services.ai.streaming import stream_chat_response
from app.services.identity.current_user import CurrentUser
from app.services.search import Passage, SearchDep

router = APIRouter(prefix="/rag", tags=["rag"])

TOP_PASSAGES = 5
SNIPPET_CHARS = 280


def _sources(passages: list[Passage]) -> str:
    if not passages:
        return "(no matching documents)"
    return "\n\n".join(
        f"[{n}] {p.title or p.source}\n{p.text}" for n, p in enumerate(passages, start=1)
    )


def _citations(passages: list[Passage]) -> list[dict]:
    return [
        {
            "id": n,
            "title": p.title or p.source,
            "source": p.source,
            "snippet": p.text[:SNIPPET_CHARS],
        }
        for n, p in enumerate(passages, start=1)
    ]


@router.post("/chat/stream", include_in_schema=False)
async def rag_chat_stream(
    payload: ChatRequest,
    user: CurrentUser,
    ai: AI,
    search: SearchDep,
    sessions: SessionFactory,
    settings: Annotated[Settings, Depends(get_settings)],
) -> StreamingResponse:
    # Retrieval failures surface as a normal 502 before any streaming starts.
    passages = await search.retrieve(payload.message, top=TOP_PASSAGES)
    system = render_prompt("rag", app_name=settings.app_name, sources=_sources(passages))
    return stream_chat_response(
        ai=ai,
        messages=conversation(system, payload),
        sessions=sessions,
        user=user,
        action="rag",
        leading_events=[("citations", _citations(passages))],
    )
