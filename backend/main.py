"""
Pharmacy AI Assistant - FastAPI backend
Medication identification + DEA regulations RAG with LangChain, optional Mem0.
"""

from __future__ import annotations

import os
import logging
from typing import List, Optional
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field, field_validator
from dotenv import load_dotenv

load_dotenv()

from prompts import expand_query
from rag_service import PharmacyRAG

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("pharmacy-ai")

rag: Optional[PharmacyRAG] = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    global rag
    logger.info("Initializing Pharmacy RAG service...")
    rag = PharmacyRAG()
    rag.ensure_index()
    logger.info("RAG ready. Documents indexed: %s", rag.document_count())
    yield
    logger.info("Shutting down.")


app = FastAPI(
    title="Pharmacy AI Assistant",
    description="Medication identification and DEA regulations assistant (Assessment III). Educational use only.",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


class ChatRequest(BaseModel):
    message: str = Field(..., min_length=1, max_length=4000)
    user_id: str = Field(default="default-user")
    session_id: Optional[str] = None
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
    sources: List[str] = []
    mode: str
    disclaimer: str = (
        "Educational/informational only. Not medical, legal, or pharmaceutical advice. "
        "Verify with licensed professionals and current official DEA/FDA sources."
    )


class HealthResponse(BaseModel):
    status: str
    documents_indexed: int
    llm_provider: str


def _health_payload() -> HealthResponse:
    return HealthResponse(
        status="healthy",
        documents_indexed=rag.document_count() if rag else 0,
        llm_provider=os.getenv("LLM_PROVIDER", "ollama"),
    )


@app.get("/health", response_model=HealthResponse)
@app.get("/api/health", response_model=HealthResponse)
def health():
    return _health_payload()


@app.post("/api/chat", response_model=ChatResponse)
def chat(req: ChatRequest):
    if not rag:
        raise HTTPException(503, "RAG service not ready")
    try:
        expanded = expand_query(req.message)
        result = rag.query(
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
    except Exception as e:
        logger.exception("Chat error")
        raise HTTPException(500, f"Query failed: {str(e)}")


@app.post("/api/meds/identify", response_model=ChatResponse)
def identify_medication(req: ChatRequest):
    # Force med_id mode without mutating caller unexpectedly beyond this request
    forced = req.model_copy(update={"mode": "med_id"})
    return chat(forced)


@app.post("/api/dea/query", response_model=ChatResponse)
def dea_query(req: ChatRequest):
    forced = req.model_copy(update={"mode": "dea"})
    return chat(forced)


@app.post("/api/ingest")
async def ingest(file: UploadFile = File(...)):
    if not rag:
        raise HTTPException(503, "RAG not ready")
    content = await file.read()
    if not content:
        raise HTTPException(400, "Empty file")
    path = rag.save_upload(file.filename or "upload.txt", content)
    count = rag.ingest_file(path)
    return {"status": "ok", "chunks_added": count, "filename": file.filename}


@app.get("/api/stats")
def stats():
    if not rag:
        raise HTTPException(503, "RAG not ready")
    return {
        "documents": rag.document_count(),
        "provider": os.getenv("LLM_PROVIDER", "ollama"),
        "mem0_enabled": bool(os.getenv("MEM0_API_KEY")),
    }


if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", 8000))
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=True)
