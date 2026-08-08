"""
LangGraph pharmacy agent.

Flow:
  classify intent → call specialist Chroma tool → grounded answer

Still RAG-only: tools search Chroma; the LLM only sees retrieved context.
"""

from __future__ import annotations

import logging
import operator
import os
from typing import Annotated, Any, TypedDict

from agents.tools import ChromaToolbelt, RagServiceRetriever, classify_intent
from agents.tracing import configure_langsmith

logger = logging.getLogger("pharmacy-agent")


class AgentState(TypedDict, total=False):
    question: str
    intent: str
    context: str
    sources: list[str]
    answer: str
    tool_used: str
    steps: Annotated[list[str], operator.add]


def _merge_sources(*lists: list[str]) -> list[str]:
    out: list[str] = []
    for lst in lists:
        for s in lst or []:
            if s not in out:
                out.append(s)
    return out


class PharmacyAgent:
    """
    Autonomous router over Chroma tools.

    Uses LangGraph when available; falls back to the same node sequence
    without LangGraph so CI/tests still exercise the agent path.
    """

    def __init__(self, rag: Any):
        configure_langsmith()
        top_k = int(os.getenv("RAG_TOP_K", "3"))
        self.rag = rag
        self.tools = ChromaToolbelt(RagServiceRetriever(rag), top_k=top_k)
        self._graph = None
        try:
            self._graph = self._build_langgraph()
            logger.info("LangGraph pharmacy agent compiled")
        except Exception as e:
            logger.warning("LangGraph unavailable (%s) — using sequential agent fallback", e)

    def _build_langgraph(self):
        from langgraph.graph import END, StateGraph

        g: StateGraph = StateGraph(AgentState)
        g.add_node("classify", self._node_classify)
        g.add_node("retrieve", self._node_retrieve)
        g.add_node("answer", self._node_answer)
        g.set_entry_point("classify")
        g.add_edge("classify", "retrieve")
        g.add_edge("retrieve", "answer")
        g.add_edge("answer", END)
        return g.compile()

    def _node_classify(self, state: AgentState) -> dict[str, Any]:
        intent = classify_intent(state.get("question", ""))
        step = f"classify→{intent}"
        logger.info("[agent] %s", step)
        return {"intent": intent, "steps": [step]}

    def _node_retrieve(self, state: AgentState) -> dict[str, Any]:
        question = state.get("question", "")
        intent = state.get("intent") or "general"
        if intent == "med_id":
            result = self.tools.search_imprints(question)
        elif intent == "dea":
            result = self.tools.search_dea(question)
        else:
            result = self.tools.search_general(question)
        step = f"tool:{result['tool']} hits={result['hit_count']}"
        logger.info("[agent] %s", step)
        return {
            "context": result.get("context") or "",
            "sources": result.get("sources") or [],
            "tool_used": result.get("tool") or "search_general",
            "steps": [step],
        }

    def _node_answer(self, state: AgentState) -> dict[str, Any]:
        question = state.get("question", "")
        intent = state.get("intent") or "general"
        context = state.get("context") or ""
        # Reuse existing grounded generation on PharmacyRAG
        try:
            out = self.rag._invoke_chain(intent, question, context)  # noqa: SLF001
            answer = out if isinstance(out, str) else str(out)
        except Exception as e:
            logger.exception("agent answer failed")
            answer = (
                "The agent could not generate an answer from the knowledge base. "
                f"({e})"
            )
        step = "answer:grounded"
        logger.info("[agent] %s intent=%s sources=%s", step, intent, state.get("sources"))
        return {"answer": answer, "steps": [step]}

    def run(self, question: str) -> dict[str, Any]:
        if not question or not str(question).strip():
            return {
                "answer": "Empty question.",
                "sources": [],
                "mode": "agent",
                "intent": "general",
                "tool_used": None,
                "steps": ["reject:empty"],
                "agent": True,
            }

        initial: AgentState = {
            "question": question.strip(),
            "steps": [],
        }

        if self._graph is not None:
            final = self._graph.invoke(initial)
        else:
            # Sequential fallback (same features, no LangGraph runtime)
            final = dict(initial)
            for node in (self._node_classify, self._node_retrieve, self._node_answer):
                upd = node(final)  # type: ignore[arg-type]
                for k, v in upd.items():
                    if k == "steps":
                        final["steps"] = list(final.get("steps") or []) + list(v or [])
                    else:
                        final[k] = v

        return {
            "answer": final.get("answer") or "",
            "sources": final.get("sources") or [],
            "mode": "agent",
            "intent": final.get("intent") or "general",
            "tool_used": final.get("tool_used"),
            "steps": list(final.get("steps") or []),
            "agent": True,
        }


def run_pharmacy_agent(rag: Any, question: str) -> dict[str, Any]:
    """Functional entry used by FastAPI."""
    agent = PharmacyAgent(rag)
    return agent.run(question)
