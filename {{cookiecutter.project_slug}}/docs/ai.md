# AI layer and UNC Azure OpenAI

All model access goes through the API (`api/app/services/ai/`). The browser never
talks to a model ([ADR 0002](adr/0002-backend-only-ai-access.md)).

## Providers

`AI_PROVIDER` selects the implementation of `AIProvider` (`services/ai/base.py`):

| Value | Use | Needs |
| --- | --- | --- |
| `mock` | local development, tests, CI | nothing; echoes the prompt, deterministic embeddings |
| `foundry` | deployed environments | UNC Azure OpenAI endpoint + deployments, and a role for the caller's identity |

Both implement the same four capabilities:

```python
from app.services.ai.base import ChatMessage
from app.services.ai.factory import AI          # FastAPI dependency

async def handler(ai: AI):
    messages = [ChatMessage(role="system", content=render_prompt("my_prompt")),
                ChatMessage(role="user", content=text)]

    result = await ai.chat(messages)                       # one response (+ usage)
    async for event in ai.stream_chat(messages): ...      # delta ... done
    invoice = await ai.complete_json(messages, Invoice)    # validated Pydantic model
    vectors = await ai.embed(["text one", "text two"])     # embeddings
```

- **Streaming to the browser:** return `stream_chat_response(...)`
  (`services/ai/streaming.py`); it handles the SSE protocol, errors after headers,
  client disconnects, the audit event and the telemetry span. The web side reads it
  with `readServerSentEvents` or reuses `ChatPanel`.
- **Structured output:** `complete_json` puts the model in JSON mode with your
  model's JSON Schema and validates the reply, raising `UpstreamServiceError` (502)
  if it doesn't match. Good for extraction and classification.
- **Prompts** are Markdown files in `api/app/prompts/`, loaded with
  `load_prompt(name)` / `render_prompt(name, **values)`. Review them like code.
- **Errors:** every SDK or network failure becomes `UpstreamServiceError` (502, the
  standard error envelope). The SDK retries 429/5xx with backoff (`AI_MAX_RETRIES`)
  and enforces `AI_REQUEST_TIMEOUT_SECONDS`.
- **Reasoning models** reject `temperature`; the provider only sends knobs you set.

## Settings

| Variable | Meaning |
| --- | --- |
| `AI_PROVIDER` | `mock` or `foundry` (deploy default: `foundry`) |
| `AZURE_AI_FOUNDRY_ENDPOINT` | e.g. `https://<resource>.openai.azure.com` |
| `AZURE_AI_FOUNDRY_DEPLOYMENT_NAME` | chat model deployment |
| `AZURE_AI_FOUNDRY_EMBEDDING_DEPLOYMENT_NAME` | embedding deployment (embeddings, RAG) |
| `AZURE_AI_FOUNDRY_API_VERSION` | Azure OpenAI API version (default `2024-10-21`) |
| `AI_REQUEST_TIMEOUT_SECONDS`, `AI_MAX_RETRIES`, `AI_MAX_OUTPUT_TOKENS` | limits |

In Azure these are GitHub variables of the `dev` environment, applied by CD
(`deploy/env-contract.json`).

## Access to UNC's Azure OpenAI (hand-off)

Authentication is keyless: `DefaultAzureCredential` uses the container app's
user-assigned managed identity in Azure (`AZURE_CLIENT_ID` is set by infra) and your
`az login` locally. No API keys exist anywhere.

The model resource belongs to UNC, so you request access rather than grant it.
Send the resource owners:

- the **principal (object) id** of the app's managed identity: `identity.principalId`
  in `infra/state/<resource-group>.json` after `deploy-identity.sh`;
- the role needed: **Cognitive Services OpenAI User** on the Azure OpenAI resource;
- which deployments you will call (chat, embeddings), and expected volume;
- the developers' accounts, if they need the same role for local testing.
{%- if cookiecutter.enable_ai_search == "yes" %}
- the **search service identity** too, for RAG (see [rag.md](rag.md)).
{%- endif %}

Then set the endpoint and deployment names as GitHub variables and run CD. The
deploy's end-to-end check fails if `/api/health` reports `ai.configured: false`.

## What gets recorded

Each model call produces:

- an **audit event** (`chat.completed`, `chat.stream_failed`, …) with provider,
  model, prompt/completion tokens and latency, but never the prompt or answer text
  (viewable at `/admin`);
- an **`ai.<operation>` span** in Application Insights with the same numbers as
  `gen_ai.*` attributes, linked to the request trace.

Need per-user quotas, cost reports, or answer feedback? Add a table and a migration,
write to it from `stream_chat_response` / the route, and enforce limits in a
dependency. Keep limits in PostgreSQL rather than memory, since containers scale out.
