"""
Pharmacy AI Assistant - FastAPI backend
Medication identification + DEA regulations RAG with LangChain, optional Mem0.
Linear RAG + LangGraph autonomous agent (Chroma tools only).
"""

from __future__ import annotations

import json
import logging
import os
import traceback
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Annotated, Any, Iterator

from dotenv import load_dotenv
from fastapi import FastAPI, File, HTTPException, Request, UploadFile
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, StreamingResponse
from pydantic import BaseModel, Field, field_validator

load_dotenv()

from prompts import expand_query  # noqa: E402
from rag_service import PharmacyRAG, RAGServiceError  # noqa: E402

logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s [%(name)s] %(message)s",
)
logger = logging.getLogger("pharmacy-ai")

rag: PharmacyRAG | None = None
_startup_error: str | None = None


def _error_body(
    *,
    code: str,
    message: str,
    detail: str | None = None,
    hint: str | None = None,
    status_code: int = 500,
) -> dict[str, Any]:
    body: dict[str, Any] = {
        "error": {
            "code": code,
            "message": message,
            "status": status_code,
        }
    }
    if detail:
        body["error"]["detail"] = detail
    if hint:
        body["error"]["hint"] = hint
    body["detail"] = message if not detail else f"{message}: {detail}"
    return body


@asynccontextmanager
async def lifespan(app: FastAPI):
    global rag, _startup_error
    logger.info("Initializing Pharmacy RAG service...")
    try:
        rag = PharmacyRAG()
        rag.ensure_index()
        count = rag.document_count()
        logger.info("RAG ready. Documents indexed: %s", count)
        if count == 0:
            logger.warning(
                "No documents indexed. Add files under backend/source_data/ "
                "or POST /api/ingest. Answers may be low-quality until then."
            )
        _startup_error = None
    except Exception as e:
        _startup_error = str(e)
        logger.exception("RAG startup failed: %s", e)
        rag = None
    yield
    logger.info("Shutting down.")


app = FastAPI(
    title="Pharmacy AI Assistant",
    description=(
        "Medication identification and DEA regulations assistant (Assessment III). "
        "Educational use only. Supports JSON, SSE streaming, and LangGraph agent chat."
    ),
    version="1.2.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    errors = exc.errors()
    logger.warning("Validation error on %s: %s", request.url.path, errors)
    return JSONResponse(
        status_code=422,
        content=_error_body(
            code="VALIDATION_ERROR",
            message="Request validation failed",
            detail=str(errors),
            hint="Check message (1–4000 chars, non-blank) and mode (general|med_id|dea).",
            status_code=422,
        ),
    )


@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    code_map = {
        400: "BAD_REQUEST",
        404: "NOT_FOUND",
        413: "PAYLOAD_TOO_LARGE",
        503: "SERVICE_UNAVAILABLE",
        500: "INTERNAL_ERROR",
    }
    code = code_map.get(exc.status_code, f"HTTP_{exc.status_code}")
    detail = exc.detail if isinstance(exc.detail, str) else str(exc.detail)
    return JSONResponse(
        status_code=exc.status_code,
        content=_error_body(
            code=code,
            message=detail,
            status_code=exc.status_code,
        ),
    )


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception):
    logger.exception("Unhandled error on %s: %s", request.url.path, exc)
    detail = str(exc)
    if os.getenv("DEBUG", "").lower() in {"1", "true", "yes"}:
        detail = f"{detail}\n{traceback.format_exc()}"
    return JSONResponse(
        status_code=500,
        content=_error_body(
            code="INTERNAL_ERROR",
            message="Unexpected server error",
            detail=detail,
            hint="Check backend logs. Set DEBUG=true for stack traces (dev only).",
            status_code=500,
        ),
    )


class ChatRequest(BaseModel):
    message: str = Field(..., min_length=1, max_length=4000)
    user_id: str = Field(default="default-user")
    session_id: str | None = None
    mode: str = Field(default="general", description="general | med_id | dea")

    @field_validator("message")
    @classmethod
    def message_not_blank(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("message must not be blank")
        return v

    @field_validator("mode")
    @classmethod
    def mode_allowed(cls, v: str) -> str:
        allowed = {"general", "med_id", "dea"}
        if v not in allowed:
            raise ValueError(f"mode must be one of {sorted(allowed)}")
        return v


class ChatResponse(BaseModel):
    answer: str
    sources: list[str] = []
    mode: str
    disclaimer: str = (
        "Educational/informational only. Not medical, legal, or pharmaceutical advice. "
        "Verify with licensed professionals and current official DEA/FDA sources."
    )


class AgentChatResponse(BaseModel):
    answer: str
    sources: list[str] = []
    mode: str = "agent"
    intent: str = "general"
    tool_used: str | None = None
    steps: list[str] = []
    agent: bool = True
    disclaimer: str = (
        "Educational/informational only. Not medical, legal, or pharmaceutical advice. "
        "Verify with licensed professionals and current official DEA/FDA sources. "
        "Agent answers are grounded only in Chroma-retrieved knowledge-base chunks."
    )


class HealthResponse(BaseModel):
    status: str
    documents_indexed: int
    llm_provider: str
    ollama_model: str | None = None
    rag_top_k: int | None = None
    startup_error: str | None = None
    chroma: dict[str, Any] | None = None


def _require_rag() -> PharmacyRAG:
    if rag is None:
        hint = (
            "Backend started but RAG failed to initialize. "
            "Check Ollama is running and models are pulled (bash scripts/run.sh)."
        )
        if _startup_error:
            hint = f"{hint} Startup error: {_startup_error}"
        raise HTTPException(
            status_code=503,
            detail=f"RAG service not ready. {hint}",
        )
    return rag


def _safe_chroma_status(service: Any) -> dict[str, Any] | None:
    """Return a real dict for HealthResponse.chroma (MagicMock is not a dict)."""
    if service is None:
        return None
    try:
        raw = service.index_status()
    except Exception as e:
        return {"ready": False, "error": str(e)}
    if isinstance(raw, dict):
        return raw
    # Mock objects / unexpected types → safe summary
    try:
        count = int(service.document_count())
    except Exception:
        count = 0
    return {
        "ready": count > 0,
        "documents_indexed": count,
        "collection": "pharmacy_docs",
        "note": "index_status unavailable; using document_count fallback",
    }


def _health_payload() -> HealthResponse:
    status = "healthy" if rag is not None else "degraded"
    return HealthResponse(
        status=status,
        documents_indexed=rag.document_count() if rag else 0,
        llm_provider=os.getenv("LLM_PROVIDER", "ollama"),
        ollama_model=os.getenv("OLLAMA_MODEL", "llama3.2:3b"),
        rag_top_k=int(os.getenv("RAG_TOP_K", "3")),
        startup_error=_startup_error,
        chroma=_safe_chroma_status(rag),
    )


@app.get("/health", response_model=HealthResponse)
@app.get("/api/health", response_model=HealthResponse)
def health():
    return _health_payload()


def _run_chat(req: ChatRequest) -> ChatResponse:
    service = _require_rag()
    try:
        expanded = expand_query(req.message)
        result = service.query(
            question=expanded,
            user_id=req.user_id,
            session_id=req.session_id,
            mode=req.mode,
        )
        return ChatResponse(
            answer=result["answer"],
            sources=result.get("sources", []),
            mode=req.mode,
        )
    except RAGServiceError as e:
        logger.warning("RAG service error [%s]: %s", e.code, e)
        raise HTTPException(
            status_code=e.http_status,
            detail=f"Query failed: {e.message}" + (f" ({e.detail})" if e.detail else ""),
        ) from e
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Chat error")
        raise HTTPException(status_code=500, detail=f"Query failed: {e!s}") from e


@app.post("/api/chat", response_model=ChatResponse)
def chat(req: ChatRequest):
    return _run_chat(req)


@app.post("/api/chat/stream")
def chat_stream(req: ChatRequest):
    """SSE stream."""
    service = _require_rag()
    expanded = expand_query(req.message)

    def event_gen() -> Iterator[str]:
        try:
            for event in service.query_stream(
                question=expanded,
                user_id=req.user_id,
                session_id=req.session_id,
                mode=req.mode,
            ):
                yield f"data: {json.dumps(event, ensure_ascii=False)}\n\n"
        except RAGServiceError as e:
            err = {
                "error": {
                    "code": e.code,
                    "message": e.message,
                    "detail": e.detail,
                    "status": e.http_status,
                }
            }
            yield f"data: {json.dumps(err)}\n\n"
        except Exception as e:
            logger.exception("Stream error")
            err = {
                "error": {
                    "code": "LLM_GENERATION_FAILED",
                    "message": str(e),
                    "status": 500,
                }
            }
            yield f"data: {json.dumps(err)}\n\n"

    return StreamingResponse(
        event_gen(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


@app.post("/api/meds/identify", response_model=ChatResponse)
def identify_medication(req: ChatRequest):
    forced = req.model_copy(update={"mode": "med_id"})
    return _run_chat(forced)


@app.post("/api/dea/query", response_model=ChatResponse)
def dea_query(req: ChatRequest):
    forced = req.model_copy(update={"mode": "dea"})
    return _run_chat(forced)


@app.post("/api/agent/chat", response_model=AgentChatResponse)
def agent_chat(req: ChatRequest):
    """LangGraph agent: classify → Chroma tool → grounded answer."""
    service = _require_rag()
    try:
        from agents.graph import run_pharmacy_agent

        expanded = expand_query(req.message)
        result = run_pharmacy_agent(service, expanded)
        return AgentChatResponse(
            answer=result.get("answer") or "",
            sources=result.get("sources") or [],
            mode="agent",
            intent=result.get("intent") or "general",
            tool_used=result.get("tool_used"),
            steps=result.get("steps") or [],
            agent=True,
        )
    except Exception as e:
        logger.exception("Agent chat failed")
        raise HTTPException(status_code=500, detail=f"Agent failed: {e!s}") from e


@app.get("/api/agent/info")
def agent_info():
    from agents.tracing import configure_langsmith

    return {
        "name": "PharmacyAgent",
        "framework": "langgraph (with sequential fallback)",
        "flow": ["classify", "retrieve (Chroma tool)", "answer (grounded)"],
        "tools": ["search_imprints", "search_dea", "search_general"],
        "knowledge_source": "Chroma only (backend/source_data embeddings)",
        "endpoint": "POST /api/agent/chat",
        "langsmith": configure_langsmith(),
    }


ALLOWED_UPLOAD_SUFFIXES = {".txt", ".md", ".pdf"}
MAX_UPLOAD_BYTES = int(os.getenv("MAX_UPLOAD_BYTES", str(5 * 1024 * 1024)))


def _path_suffix(name: str) -> str:
    return Path(name).suffix.lower()


@app.post("/api/ingest")
async def ingest(file: Annotated[UploadFile, File()]):
    service = _require_rag()
    filename = file.filename or "upload.txt"
    suffix = _path_suffix(filename)
    if suffix not in ALLOWED_UPLOAD_SUFFIXES:
        raise HTTPException(
            status_code=400,
            detail=(
                f"Unsupported file type '{suffix}'. Allowed: {sorted(ALLOWED_UPLOAD_SUFFIXES)}"
            ),
        )
    content = await file.read()
    if not content:
        raise HTTPException(status_code=400, detail="Empty file")
    if len(content) > MAX_UPLOAD_BYTES:
        raise HTTPException(
            status_code=413,
            detail=f"File exceeds max size of {MAX_UPLOAD_BYTES} bytes",
        )
    try:
        path = service.save_upload(filename, content)
        count = service.ingest_file(path)
        if count == 0:
            return {
                "status": "warning",
                "chunks_added": 0,
                "filename": filename,
                "message": "File saved but produced no indexable chunks (empty or unreadable).",
            }
        return {"status": "ok", "chunks_added": count, "filename": filename}
    except RAGServiceError as e:
        raise HTTPException(status_code=e.http_status, detail=e.message) from e
    except Exception as e:
        logger.exception("Ingest failed for %s", filename)
        raise HTTPException(status_code=500, detail=f"Ingest failed: {e}") from e


@app.get("/api/stats")
def stats():
    service = _require_rag()
    from agents.tracing import configure_langsmith

    return {
        "documents": service.document_count(),
        "provider": os.getenv("LLM_PROVIDER", "ollama"),
        "ollama_model": os.getenv("OLLAMA_MODEL", "llama3.2:3b"),
        "rag_top_k": int(os.getenv("RAG_TOP_K", "3")),
        "mem0_enabled": bool(os.getenv("MEM0_API_KEY")),
        "startup_error": _startup_error,
        "chroma": _safe_chroma_status(service),
        "agent": {
            "endpoint": "/api/agent/chat",
            "tools": ["search_imprints", "search_dea", "search_general"],
            "langsmith": configure_langsmith(),
        },
        "note": "Answers are grounded only in Chroma-retrieved chunks from source_data",
    }


if __name__ == "__main__":
    import uvicorn

    port = int(os.getenv("PORT", 8000))
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=True)
