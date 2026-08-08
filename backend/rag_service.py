"""RAG service for Pharmacy AI Assistant - hybrid retrieval + LangChain + optional Mem0."""

from __future__ import annotations

import os
import logging
from pathlib import Path
from typing import Any, Dict, List, Optional

from langchain_core.documents import Document
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langchain_community.vectorstores import Chroma
from langchain_ollama import ChatOllama, OllamaEmbeddings
from langchain_core.output_parsers import StrOutputParser
from langchain_core.runnables import RunnablePassthrough

from prompts import RAG_PROMPT, MED_ID_PROMPT, DEA_QUERY_PROMPT

logger = logging.getLogger("pharmacy-rag")

DATA_PATH = Path(os.getenv("DATA_PATH", "source_data"))
CHROMA_PATH = Path(os.getenv("CHROMA_PATH", "./chroma_db"))
CHUNK_SIZE = 900
CHUNK_OVERLAP = 150


class PharmacyRAG:
    def __init__(self):
        self.provider = os.getenv("LLM_PROVIDER", "ollama").lower()
        self.embeddings = self._build_embeddings()
        self.llm = self._build_llm()
        self.vectorstore: Optional[Chroma] = None
        self.mem0 = self._init_mem0()
        self.splitter = RecursiveCharacterTextSplitter(
            chunk_size=CHUNK_SIZE, chunk_overlap=CHUNK_OVERLAP,
            separators=["\n\n", "\n", ". ", " ", ""],
        )

    def _build_embeddings(self):
        model = os.getenv("OLLAMA_EMBED_MODEL", "nomic-embed-text")
        base = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")
        return OllamaEmbeddings(model=model, base_url=base)

    def _build_llm(self):
        if self.provider == "openai":
            from langchain_openai import ChatOpenAI
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
            logger.warning("Mem0 init failed: %s", e)
            return None

    def ensure_index(self):
        CHROMA_PATH.mkdir(parents=True, exist_ok=True)
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
                logger.warning("Could not load existing index: %s", e)

        docs = self._load_source_docs()
        if not docs:
            self.vectorstore = Chroma(
                persist_directory=str(CHROMA_PATH),
                embedding_function=self.embeddings,
                collection_name="pharmacy_docs",
            )
            return

        chunks = self.splitter.split_documents(docs)
        self.vectorstore = Chroma.from_documents(
            documents=chunks, embedding=self.embeddings,
            persist_directory=str(CHROMA_PATH), collection_name="pharmacy_docs",
        )
        logger.info("Indexed %d chunks from %d docs", len(chunks), len(docs))

    def _load_source_docs(self) -> List[Document]:
        docs: List[Document] = []
        for base in [DATA_PATH, Path("source_data"), Path("/app/source_data"), Path("backend/source_data")]:
            if not base.exists():
                continue
            for p in base.rglob("*"):
                if p.suffix.lower() in {".txt", ".md"} and p.is_file():
                    try:
                        text = p.read_text(encoding="utf-8", errors="ignore")
                        docs.append(Document(page_content=text, metadata={"source": p.name}))
                    except Exception:
                        pass
            if docs:
                break
        return docs

    def document_count(self) -> int:
        if not self.vectorstore:
            return 0
        try:
            return self.vectorstore._collection.count()
        except Exception:
            return 0

    def save_upload(self, filename: str, content: bytes) -> Path:
        dest_dir = Path(os.getenv("DATA_PATH", "./source_data"))
        dest_dir.mkdir(parents=True, exist_ok=True)
        path = dest_dir / filename
        path.write_bytes(content)
        return path

    def ingest_file(self, path: Path) -> int:
        text = ""
        if path.suffix.lower() in {".txt", ".md"}:
            text = path.read_text(encoding="utf-8", errors="ignore")
        elif path.suffix.lower() == ".pdf":
            try:
                from pypdf import PdfReader
                reader = PdfReader(str(path))
                text = "\n".join(page.extract_text() or "" for page in reader.pages)
            except Exception as e:
                logger.error("PDF extract failed: %s", e)
                return 0
        if not text.strip():
            return 0
        doc = Document(page_content=text, metadata={"source": path.name})
        chunks = self.splitter.split_documents([doc])
        self.vectorstore.add_documents(chunks)
        return len(chunks)

    def _retrieve(self, query: str, k: int = 6) -> List[Document]:
        if not self.vectorstore:
            return []
        return self.vectorstore.similarity_search(query, k=k)

    def query(self, question: str, user_id: str = "default", session_id: Optional[str] = None, mode: str = "general") -> Dict[str, Any]:
        docs = self._retrieve(question)
        context = "\n\n".join(f"[Source: {d.metadata.get('source', 'unknown')}]\n{d.page_content}" for d in docs)
        sources = list({d.metadata.get("source", "unknown") for d in docs})

        mem_context = ""
        if self.mem0:
            try:
                memories = self.mem0.search(question, user_id=user_id)
                if memories:
                    mem_context = "\nPrior relevant memories:\n" + str(memories)[:1500]
            except Exception:
                pass

        full_context = context + mem_context

        if mode == "med_id":
            chain = MED_ID_PROMPT | self.llm | StrOutputParser()
            answer = chain.invoke({"query": question, "context": full_context})
        elif mode == "dea":
            chain = DEA_QUERY_PROMPT | self.llm | StrOutputParser()
            answer = chain.invoke({"query": question, "context": full_context})
        else:
            chain = ({"context": lambda _: full_context, "question": RunnablePassthrough()} | RAG_PROMPT | self.llm | StrOutputParser())
            answer = chain.invoke(question)

        if self.mem0:
            try:
                self.mem0.add([{"role": "user", "content": question}, {"role": "assistant", "content": answer[:2000]}], user_id=user_id)
            except Exception:
                pass

        return {"answer": answer, "sources": sources}
