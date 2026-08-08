"""
Chroma-backed tools for the pharmacy agent.

These are the ONLY knowledge sources the agent may use — no free-world search.
Modular: wrap any object that implements retrieve_docs(query, k) -> list[{content, source}].
"""

from __future__ import annotations

import logging
import re
from typing import Any, Protocol

logger = logging.getLogger("pharmacy-agent")


class Retriever(Protocol):
    def retrieve_docs(self, query: str, k: int = 3) -> list[dict[str, str]]: ...


def _docs_to_context(docs: list[dict[str, str]]) -> tuple[str, list[str]]:
    if not docs:
        return "", []
    parts = []
    sources: list[str] = []
    for d in docs:
        src = d.get("source") or "unknown"
        body = d.get("content") or ""
        parts.append(f"[Source: {src}]\n{body}")
        if src not in sources:
            sources.append(src)
    return "\n\n".join(parts), sources


class ChromaToolbelt:
    """Three specialist retrieval tools over the same Chroma index."""

    def __init__(self, retriever: Retriever, top_k: int = 3):
        self.retriever = retriever
        self.top_k = max(1, top_k)

    def search_imprints(self, query: str) -> dict[str, Any]:
        """Search knowledge base for tablet imprint / medication identity."""
        q = f"tablet imprint medication identification {query}"
        docs = self.retriever.retrieve_docs(q, k=self.top_k)
        context, sources = _docs_to_context(docs)
        logger.info("tool search_imprints hits=%s sources=%s", len(docs), sources)
        return {
            "tool": "search_imprints",
            "query": query,
            "context": context,
            "sources": sources,
            "hit_count": len(docs),
        }

    def search_dea(self, query: str) -> dict[str, Any]:
        """Search knowledge base for DEA schedules and controlled-substance rules."""
        q = f"DEA schedule controlled substance refill {query}"
        docs = self.retriever.retrieve_docs(q, k=self.top_k)
        context, sources = _docs_to_context(docs)
        logger.info("tool search_dea hits=%s sources=%s", len(docs), sources)
        return {
            "tool": "search_dea",
            "query": query,
            "context": context,
            "sources": sources,
            "hit_count": len(docs),
        }

    def search_general(self, query: str) -> dict[str, Any]:
        """General pharmacy knowledge-base search."""
        docs = self.retriever.retrieve_docs(query, k=self.top_k)
        context, sources = _docs_to_context(docs)
        logger.info("tool search_general hits=%s sources=%s", len(docs), sources)
        return {
            "tool": "search_general",
            "query": query,
            "context": context,
            "sources": sources,
            "hit_count": len(docs),
        }


class RagServiceRetriever:
    """Adapter: PharmacyRAG → Retriever protocol without changing RAG core."""

    def __init__(self, rag: Any):
        self.rag = rag

    def retrieve_docs(self, query: str, k: int = 3) -> list[dict[str, str]]:
        if self.rag is None:
            return []
        try:
            docs = self.rag._retrieve(query, k=k)  # noqa: SLF001 — intentional bridge
        except Exception as e:
            logger.warning("retrieve_docs failed: %s", e)
            return []
        out: list[dict[str, str]] = []
        for d in docs or []:
            meta = getattr(d, "metadata", None) or {}
            content = getattr(d, "page_content", None) or str(d)
            out.append(
                {
                    "content": content,
                    "source": str(meta.get("source", "unknown")),
                }
            )
        return out


_IMPRINT_RE = re.compile(
    r"\b(imprint|tablet|capsule|pill|ndc|identify|identification|what\s+(drug|med)|m\d{3,})\b",
    re.I,
)
_DEA_RE = re.compile(
    r"\b(dea|schedule\s*(i{1,3}|iv|v|1|2|3|4|5)|controlled|refill|cii|ciii|civ|cv|c-?2|c-?3)\b",
    re.I,
)


def classify_intent(question: str) -> str:
    """
    Lightweight autonomous routing (no extra LLM call).
    Returns: med_id | dea | general
    """
    q = question or ""
    if _IMPRINT_RE.search(q):
        return "med_id"
    if _DEA_RE.search(q):
        return "dea"
    return "general"
