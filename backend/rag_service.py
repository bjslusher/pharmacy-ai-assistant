"""RAG service for Pharmacy AI Assistant - hybrid retrieval + LangChain + optional Mem0."""

from __future__ import annotations

import logging
import os
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


class RAGServiceError(Exception):
    """Typed RAG failure with API-friendly fields."""

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

    def _build_embeddings(self):
        model = os.getenv("OLLAMA_EMBED_MODEL", "nomic-embed-text")
        base = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")
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
        model = os.getenv("OLLAMA_MODEL", "llama3")
        base = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")
        return ChatOllama(model=model, base_url=base, temperature=0.1)

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
        try:
            CHROMA_PATH.mkdir(parents=True, exist_ok=True)
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
                if self.document_count() > 0:
                    logger.info("Loaded existing Chroma index")
                    return
            except Exception as e:
                logger.warning("Could not load existing index (will rebuild): %s", e)

        docs = self._load_source_docs()
        if not docs:
            logger.warning("No source documents found under %s", DATA_PATH)
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

        try:
            chunks = self.splitter.split_documents(docs)
            self.vectorstore = Chroma.from_documents(
                documents=chunks,
                embedding=self.embeddings,
                persist_directory=str(CHROMA_PATH),
                collection_name="pharmacy_docs",
            )
            logger.info("Indexed %d chunks from %d docs", len(chunks), len(docs))
        except Exception as e:
            raise RAGServiceError(
                "Failed to build vector index (is the embedding model available?)",
                code="INDEX_BUILD_FAILED",
                detail=str(e),
                http_status=503,
            ) from e

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
            return len(chunks)
        except Exception as e:
            raise RAGServiceError(
                "Failed to index uploaded document",
                code="INGEST_INDEX_FAILED",
                detail=str(e),
                http_status=500,
            ) from e

    def _retrieve(self, query: str, k: int = 6) -> list[Document]:
        if not self.vectorstore:
            return []
        try:
            return self.vectorstore.similarity_search(query, k=k)
        except Exception as e:
            logger.warning("Retrieval failed: %s", e)
            raise RAGServiceError(
                "Document retrieval failed",
                code="RETRIEVAL_FAILED",
                detail=str(e),
                http_status=503,
            ) from e

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
            docs = self._retrieve(question)
        except RAGServiceError:
            raise

        context = "\n\n".join(
            f"[Source: {d.metadata.get('source', 'unknown')}]\n{d.page_content}"
            for d in docs
        )
        sources = list({d.metadata.get("source", "unknown") for d in docs})

        if not docs:
            logger.info("No retrieved docs for query (mode=%s)", mode)

        mem_context = ""
        if self.mem0:
            try:
                memories = self.mem0.search(question, user_id=user_id)
                if memories:
                    mem_context = "\nPrior relevant memories:\n" + str(memories)[:1500]
            except Exception as e:
                logger.warning("Mem0 search failed (non-fatal): %s", e)

        full_context = context + mem_context

        try:
            if mode == "med_id":
                chain = MED_ID_PROMPT | self.llm | StrOutputParser()
                answer = chain.invoke({"query": question, "context": full_context})
            elif mode == "dea":
                chain = DEA_QUERY_PROMPT | self.llm | StrOutputParser()
                answer = chain.invoke({"query": question, "context": full_context})
            else:
                chain = (
                    {"context": lambda _: full_context, "question": RunnablePassthrough()}
                    | RAG_PROMPT
                    | self.llm
                    | StrOutputParser()
                )
                answer = chain.invoke(question)
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
