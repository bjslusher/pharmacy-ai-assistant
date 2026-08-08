"""RAG service for Pharmacy AI Assistant — Chroma is the ONLY knowledge source."""

from __future__ import annotations

import logging
import os
import sys
from collections.abc import Iterator
from pathlib import Path
from typing import Any

from langchain_community.vectorstores import Chroma
from langchain_core.documents import Document
from langchain_core.output_parsers import StrOutputParser
from langchain_core.runnables import RunnablePassthrough
from langchain_ollama import ChatOllama, OllamaEmbeddings
from langchain_text_splitters import RecursiveCharacterTextSplitter

from prompts import DEA_QUERY_PROMPT, MED_ID_PROMPT, RAG_PROMPT

logger = logging.getLogger("pharmacy-rag")

DATA_PATH = Path(os.getenv("DATA_PATH", "source_data"))
CHROMA_PATH = Path(os.getenv("CHROMA_PATH", "./chroma_db"))
CHUNK_SIZE = 900
CHUNK_OVERLAP = 150

DEFAULT_TOP_K = int(os.getenv("RAG_TOP_K", "3"))
DEFAULT_NUM_PREDICT = int(os.getenv("OLLAMA_NUM_PREDICT", "350"))
DEFAULT_NUM_CTX = int(os.getenv("OLLAMA_NUM_CTX", "2048"))
DEFAULT_MODEL = os.getenv("OLLAMA_MODEL", "llama3.2:3b")


def _banner(msg: str) -> None:
    """Loud console line for orchestrator / docker logs (stdout + logger)."""
    line = f"[CHROMA] {msg}"
    print(line, flush=True, file=sys.stdout)
    logger.info("%s", msg)


class RAGServiceError(Exception):
    def __init__(
        self,
        message: str,
        *,
        code: str = "RAG_ERROR",
        detail: str | None = None,
        http_status: int = 500,
    ):
        super().__init__(message)
        self.message = message
        self.code = code
        self.detail = detail
        self.http_status = http_status


class PharmacyRAG:
    def __init__(self):
        self.provider = os.getenv("LLM_PROVIDER", "ollama").lower()
        self.top_k = max(1, int(os.getenv("RAG_TOP_K", str(DEFAULT_TOP_K))))
        try:
            self.embeddings = self._build_embeddings()
            self.llm = self._build_llm()
        except Exception as e:
            logger.exception("Failed to build LLM/embeddings")
            raise RAGServiceError(
                "Failed to initialize LLM or embeddings",
                code="LLM_INIT_FAILED",
                detail=str(e),
                http_status=503,
            ) from e
        self.vectorstore: Chroma | None = None
        self.mem0 = self._init_mem0()
        self.splitter = RecursiveCharacterTextSplitter(
            chunk_size=CHUNK_SIZE,
            chunk_overlap=CHUNK_OVERLAP,
            separators=["\n\n", "\n", ". ", " ", ""],
        )
        _banner(
            f"RAG config provider={self.provider} model={os.getenv('OLLAMA_MODEL', DEFAULT_MODEL)} "
            f"top_k={self.top_k} chroma_path={CHROMA_PATH}"
        )

    def _build_embeddings(self):
        model = os.getenv("OLLAMA_EMBED_MODEL", "nomic-embed-text")
        base = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")
        _banner(f"Embedding model = {model} @ {base} (used to VECTORIZE docs into Chroma)")
        return OllamaEmbeddings(model=model, base_url=base)

    def _build_llm(self):
        if self.provider == "openai":
            from langchain_openai import ChatOpenAI

            if not os.getenv("OPENAI_API_KEY"):
                raise RAGServiceError(
                    "OPENAI_API_KEY is required when LLM_PROVIDER=openai",
                    code="MISSING_API_KEY",
                    http_status=503,
                )
            return ChatOpenAI(model="gpt-4o-mini", temperature=0.1)

        model = os.getenv("OLLAMA_MODEL", DEFAULT_MODEL)
        base = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")
        num_predict = int(os.getenv("OLLAMA_NUM_PREDICT", str(DEFAULT_NUM_PREDICT)))
        num_ctx = int(os.getenv("OLLAMA_NUM_CTX", str(DEFAULT_NUM_CTX)))
        return ChatOllama(
            model=model,
            base_url=base,
            temperature=0.1,
            num_predict=num_predict,
            num_ctx=num_ctx,
            keep_alive="10m",
        )

    def _init_mem0(self):
        key = os.getenv("MEM0_API_KEY")
        if not key:
            return None
        try:
            from mem0 import MemoryClient

            return MemoryClient(api_key=key)
        except Exception as e:
            logger.warning("Mem0 init failed (continuing without memory): %s", e)
            return None

    def ensure_index(self):
        """Create or load ChromaDB. This is the ONLY knowledge store for RAG answers."""
        _banner(f"ensure_index starting — path={CHROMA_PATH.resolve()}")
        try:
            CHROMA_PATH.mkdir(parents=True, exist_ok=True)
            _banner(f"Chroma directory ready: {CHROMA_PATH.resolve()}")
        except OSError as e:
            raise RAGServiceError(
                "Cannot create Chroma data directory",
                code="INDEX_PATH_ERROR",
                detail=str(e),
                http_status=500,
            ) from e

        if any(CHROMA_PATH.iterdir()):
            try:
                self.vectorstore = Chroma(
                    persist_directory=str(CHROMA_PATH),
                    embedding_function=self.embeddings,
                    collection_name="pharmacy_docs",
                )
                count = self.document_count()
                if count > 0:
                    _banner(
                        f"LOADED existing Chroma index — collection=pharmacy_docs "
                        f"documents/chunks={count} path={CHROMA_PATH.resolve()}"
                    )
                    return
                _banner("Existing Chroma dir was empty — will rebuild from source_data")
            except Exception as e:
                _banner(f"Could not load existing index (will rebuild): {e}")

        docs = self._load_source_docs()
        if not docs:
            _banner(f"WARNING: No source documents under {DATA_PATH} — empty Chroma store")
            try:
                self.vectorstore = Chroma(
                    persist_directory=str(CHROMA_PATH),
                    embedding_function=self.embeddings,
                    collection_name="pharmacy_docs",
                )
            except Exception as e:
                raise RAGServiceError(
                    "Failed to create empty vector store",
                    code="INDEX_CREATE_FAILED",
                    detail=str(e),
                    http_status=500,
                ) from e
            return

        sources = sorted({d.metadata.get("source", "?") for d in docs})
        _banner(f"Embedding {len(docs)} source file(s) into Chroma: {sources}")
        try:
            chunks = self.splitter.split_documents(docs)
            _banner(f"Split into {len(chunks)} chunks — calling nomic-embed-text via Ollama…")
            self.vectorstore = Chroma.from_documents(
                documents=chunks,
                embedding=self.embeddings,
                persist_directory=str(CHROMA_PATH),
                collection_name="pharmacy_docs",
            )
            final = self.document_count()
            _banner(
                f"INDEX BUILT — chunks={len(chunks)} stored={final} "
                f"collection=pharmacy_docs path={CHROMA_PATH.resolve()}"
            )
            _banner("Chroma is now the ONLY knowledge source for RAG answers")
        except Exception as e:
            raise RAGServiceError(
                "Failed to build vector index (is nomic-embed-text pulled in Ollama?)",
                code="INDEX_BUILD_FAILED",
                detail=str(e),
                http_status=503,
            ) from e

    def index_status(self) -> dict[str, Any]:
        """Telemetry for /api/health and orchestrator."""
        count = self.document_count()
        sources: list[str] = []
        try:
            if self.vectorstore is not None:
                raw = self.vectorstore._collection.get(include=["metadatas"])
                metas = raw.get("metadatas") or []
                sources = sorted(
                    {
                        (m or {}).get("source", "unknown")
                        for m in metas
                        if isinstance(m, dict)
                    }
                )
        except Exception as e:
            logger.debug("index_status sources failed: %s", e)
        return {
            "path": str(CHROMA_PATH.resolve()),
            "documents_indexed": count,
            "sources": sources,
            "embedding_model": os.getenv("OLLAMA_EMBED_MODEL", "nomic-embed-text"),
            "collection": "pharmacy_docs",
            "ready": count > 0,
        }

    def _load_source_docs(self) -> list[Document]:
        docs: list[Document] = []
        for base in [
            DATA_PATH,
            Path("source_data"),
            Path("/app/source_data"),
            Path("backend/source_data"),
        ]:
            if not base.exists():
                continue
            for p in base.rglob("*"):
                if p.suffix.lower() in {".txt", ".md"} and p.is_file():
                    try:
                        text = p.read_text(encoding="utf-8", errors="ignore")
                        if text.strip():
                            docs.append(
                                Document(
                                    page_content=text,
                                    metadata={"source": p.name},
                                )
                            )
                            _banner(f"Loaded source file: {p.name} ({len(text)} chars)")
                    except OSError as e:
                        logger.warning("Skipping unreadable file %s: %s", p, e)
            if docs:
                break
        return docs

    def document_count(self) -> int:
        if not self.vectorstore:
            return 0
        try:
            return self.vectorstore._collection.count()
        except Exception as e:
            logger.debug("document_count failed: %s", e)
            return 0

    def save_upload(self, filename: str, content: bytes) -> Path:
        safe_name = Path(filename).name
        if not safe_name or safe_name in {".", ".."}:
            raise RAGServiceError(
                "Invalid upload filename",
                code="INVALID_FILENAME",
                http_status=400,
            )
        dest_dir = Path(os.getenv("DATA_PATH", "./source_data"))
        try:
            dest_dir.mkdir(parents=True, exist_ok=True)
            path = dest_dir / safe_name
            path.write_bytes(content)
            return path
        except OSError as e:
            raise RAGServiceError(
                "Failed to save upload",
                code="UPLOAD_SAVE_FAILED",
                detail=str(e),
                http_status=500,
            ) from e

    def ingest_file(self, path: Path) -> int:
        if not self.vectorstore:
            raise RAGServiceError(
                "Vector store not initialized",
                code="INDEX_NOT_READY",
                http_status=503,
            )
        text = ""
        suffix = path.suffix.lower()
        try:
            if suffix in {".txt", ".md"}:
                text = path.read_text(encoding="utf-8", errors="ignore")
            elif suffix == ".pdf":
                try:
                    from pypdf import PdfReader

                    reader = PdfReader(str(path))
                    text = "\n".join(page.extract_text() or "" for page in reader.pages)
                except Exception as e:
                    logger.error("PDF extract failed for %s: %s", path, e)
                    raise RAGServiceError(
                        "PDF extraction failed",
                        code="PDF_EXTRACT_FAILED",
                        detail=str(e),
                        http_status=400,
                    ) from e
            else:
                raise RAGServiceError(
                    f"Unsupported file type: {suffix}",
                    code="UNSUPPORTED_TYPE",
                    http_status=400,
                )
        except RAGServiceError:
            raise
        except OSError as e:
            raise RAGServiceError(
                "Could not read uploaded file",
                code="FILE_READ_FAILED",
                detail=str(e),
                http_status=400,
            ) from e

        if not text.strip():
            return 0
        try:
            doc = Document(page_content=text, metadata={"source": path.name})
            chunks = self.splitter.split_documents([doc])
            self.vectorstore.add_documents(chunks)
            _banner(f"Ingested upload {path.name} → {len(chunks)} chunks into Chroma")
            return len(chunks)
        except Exception as e:
            raise RAGServiceError(
                "Failed to index uploaded document",
                code="INGEST_INDEX_FAILED",
                detail=str(e),
                http_status=500,
            ) from e

    def _retrieve(self, query: str, k: int | None = None) -> list[Document]:
        if not self.vectorstore:
            return []
        k = k if k is not None else self.top_k
        try:
            docs = self.vectorstore.similarity_search(query, k=k)
            _banner(
                f"RETRIEVE from Chroma k={k} hits={len(docs)} "
                f"sources={[d.metadata.get('source') for d in docs]}"
            )
            return docs
        except Exception as e:
            logger.warning("Retrieval failed: %s", e)
            raise RAGServiceError(
                "Document retrieval failed",
                code="RETRIEVAL_FAILED",
                detail=str(e),
                http_status=503,
            ) from e

    def _build_context(
        self,
        question: str,
        user_id: str = "default",
    ) -> tuple[str, list[str]]:
        docs = self._retrieve(question)
        context = "\n\n".join(
            f"[Source: {d.metadata.get('source', 'unknown')}]\n{d.page_content}" for d in docs
        )
        sources = list({d.metadata.get("source", "unknown") for d in docs})
        if not docs:
            _banner("No Chroma hits for query — LLM will only see empty context")

        if self.mem0:
            try:
                memories = self.mem0.search(question, user_id=user_id)
                if memories:
                    context = context + "\nPrior relevant memories:\n" + str(memories)[:800]
            except Exception as e:
                logger.warning("Mem0 search failed (non-fatal): %s", e)

        return context, sources

    def _prompt_for_mode(self, mode: str):
        if mode == "med_id":
            return MED_ID_PROMPT
        if mode == "dea":
            return DEA_QUERY_PROMPT
        return RAG_PROMPT

    def _invoke_chain(self, mode: str, question: str, context: str) -> str:
        if mode == "med_id":
            chain = MED_ID_PROMPT | self.llm | StrOutputParser()
            return chain.invoke({"query": question, "context": context})
        if mode == "dea":
            chain = DEA_QUERY_PROMPT | self.llm | StrOutputParser()
            return chain.invoke({"query": question, "context": context})
        chain = (
            {"context": lambda _: context, "question": RunnablePassthrough()}
            | RAG_PROMPT
            | self.llm
            | StrOutputParser()
        )
        return chain.invoke(question)

    def _stream_chain(self, mode: str, question: str, context: str) -> Iterator[str]:
        if mode == "med_id":
            chain = MED_ID_PROMPT | self.llm | StrOutputParser()
            yield from chain.stream({"query": question, "context": context})
            return
        if mode == "dea":
            chain = DEA_QUERY_PROMPT | self.llm | StrOutputParser()
            yield from chain.stream({"query": question, "context": context})
            return
        chain = (
            {"context": lambda _: context, "question": RunnablePassthrough()}
            | RAG_PROMPT
            | self.llm
            | StrOutputParser()
        )
        yield from chain.stream(question)

    def query(
        self,
        question: str,
        user_id: str = "default",
        session_id: str | None = None,
        mode: str = "general",
    ) -> dict[str, Any]:
        if not question or not str(question).strip():
            raise RAGServiceError(
                "Empty question",
                code="EMPTY_QUERY",
                http_status=400,
            )

        try:
            context, sources = self._build_context(question, user_id=user_id)
        except RAGServiceError:
            raise

        try:
            answer = self._invoke_chain(mode, question, context)
        except RAGServiceError:
            raise
        except Exception as e:
            logger.exception("LLM generation failed")
            raise RAGServiceError(
                "LLM generation failed (is Ollama running and the model pulled?)",
                code="LLM_GENERATION_FAILED",
                detail=str(e),
                http_status=503,
            ) from e

        if self.mem0:
            try:
                self.mem0.add(
                    [
                        {"role": "user", "content": question},
                        {"role": "assistant", "content": answer[:2000]},
                    ],
                    user_id=user_id,
                )
            except Exception as e:
                logger.warning("Mem0 store failed (non-fatal): %s", e)

        return {"answer": answer, "sources": sources}

    def query_stream(
        self,
        question: str,
        user_id: str = "default",
        session_id: str | None = None,
        mode: str = "general",
    ) -> Iterator[dict[str, Any]]:
        if not question or not str(question).strip():
            raise RAGServiceError(
                "Empty question",
                code="EMPTY_QUERY",
                http_status=400,
            )

        context, sources = self._build_context(question, user_id=user_id)
        pieces: list[str] = []
        try:
            for token in self._stream_chain(mode, question, context):
                if not token:
                    continue
                pieces.append(token)
                yield {"token": token}
        except Exception as e:
            logger.exception("LLM stream failed")
            raise RAGServiceError(
                "LLM generation failed (is Ollama running and the model pulled?)",
                code="LLM_GENERATION_FAILED",
                detail=str(e),
                http_status=503,
            ) from e

        answer = "".join(pieces)
        if self.mem0 and answer:
            try:
                self.mem0.add(
                    [
                        {"role": "user", "content": question},
                        {"role": "assistant", "content": answer[:2000]},
                    ],
                    user_id=user_id,
                )
            except Exception as e:
                logger.warning("Mem0 store failed (non-fatal): %s", e)

        yield {"done": True, "answer": answer, "sources": sources, "mode": mode}
