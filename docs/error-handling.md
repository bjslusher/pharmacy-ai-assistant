# Error handling details

This project returns **structured JSON errors** from the API and typed failures from the RAG layer so clients and operators can tell validation problems from infrastructure outages.

## API error shape

Most error responses look like:

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Request validation failed",
    "status": 422,
    "detail": "[...pydantic errors...]",
    "hint": "Check message (1–4000 chars, non-blank) and mode (general|med_id|dea)."
  },
  "detail": "Request validation failed: [...]"
}
```

- `error.code` — stable machine-readable code  
- `error.message` — short human summary  
- `error.detail` — optional extra diagnostics  
- `error.hint` — optional recovery suggestion  
- `detail` — FastAPI-compatible string for older clients/tests  

Set `DEBUG=true` on the backend to include stack traces in unhandled 500 responses (**dev only**).

## HTTP status map

| Status | Typical cause |
|--------|----------------|
| **400** | Empty upload, bad filename, unsupported type, PDF extract failure |
| **413** | Upload larger than `MAX_UPLOAD_BYTES` (default 5 MB) |
| **422** | Invalid body: blank message, bad `mode`, message > 4000 chars |
| **500** | Unexpected server error, index write failure |
| **503** | RAG not ready, LLM/embeddings init failed, Ollama down, retrieval/generation failed |

## RAG error codes (`RAGServiceError`)

| Code | Meaning |
|------|---------|
| `LLM_INIT_FAILED` | Could not construct LLM or embeddings |
| `MISSING_API_KEY` | `LLM_PROVIDER=openai` but no `OPENAI_API_KEY` |
| `INDEX_PATH_ERROR` | Cannot create Chroma directory |
| `INDEX_CREATE_FAILED` / `INDEX_BUILD_FAILED` | Vector store create/build failed |
| `INDEX_NOT_READY` | Ingest before index exists |
| `RETRIEVAL_FAILED` | Similarity search failed |
| `LLM_GENERATION_FAILED` | Model call failed (often Ollama not running / model not pulled) |
| `EMPTY_QUERY` | Empty question string |
| `INVALID_FILENAME` / `UPLOAD_SAVE_FAILED` / `FILE_READ_FAILED` | Upload path issues |
| `PDF_EXTRACT_FAILED` / `UNSUPPORTED_TYPE` / `INGEST_INDEX_FAILED` | Ingest pipeline |

Mem0 failures are **non-fatal** (logged, request continues).

## Startup / health

- If RAG init fails at startup, the API still boots in **degraded** mode.
- `GET /api/health` returns `status: "degraded"` and optional `startup_error`.
- Chat/ingest/stats return **503** until RAG is available.

## Orchestrator (`scripts/run.sh`)

| Situation | Behavior |
|-----------|----------|
| Docker missing | Exit 1 with install hint |
| Compose missing | Exit 1 with install hint |
| Backend health timeout | Warning (does not kill containers); use `logs` / `status` |
| Model pull failure | Warning; retry with `docker compose exec ollama ollama pull ...` |
| Unknown subcommand | Exit 1 + usage |

## Client checklist

1. On **422** — fix payload (`message`, `mode`).  
2. On **503** — run `bash scripts/run.sh status` and ensure Ollama models exist.  
3. On **500** — check container logs: `bash scripts/run.sh logs`.  
4. Prefer `error.code` over parsing free-text `detail` strings.
