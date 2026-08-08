"""Unit tests for pharmacy agent routing + tools (no Ollama required)."""

from __future__ import annotations

import sys
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock

BACKEND = Path(__file__).resolve().parent.parent
if str(BACKEND) not in sys.path:
    sys.path.insert(0, str(BACKEND))

from agents.graph import PharmacyAgent  # noqa: E402
from agents.tools import ChromaToolbelt, classify_intent  # noqa: E402


class TestClassifyIntent:
    def test_imprint(self) -> None:
        assert classify_intent("What drug has imprint M367?") == "med_id"

    def test_dea(self) -> None:
        assert classify_intent("Can Schedule II prescriptions be refilled?") == "dea"

    def test_general(self) -> None:
        assert classify_intent("What are pharmacist responsibilities?") == "general"


class TestChromaToolbelt:
    def test_search_imprints_uses_retriever(self) -> None:
        retriever = MagicMock()
        retriever.retrieve_docs.return_value = [
            {"content": "M367 hydrocodone", "source": "common_controlled_imprints.txt"}
        ]
        belt = ChromaToolbelt(retriever, top_k=2)
        out = belt.search_imprints("M367")
        assert out["tool"] == "search_imprints"
        assert out["hit_count"] == 1
        assert "common_controlled_imprints.txt" in out["sources"]
        retriever.retrieve_docs.assert_called()


class TestPharmacyAgent:
    def test_agent_run_dea_path(self) -> None:
        rag = MagicMock()
        doc = SimpleNamespace(
            page_content="Schedule II may not be refilled under federal rules.",
            metadata={"source": "dea_schedules_overview.txt"},
        )
        rag._retrieve.return_value = [doc]
        rag._invoke_chain.return_value = "No federal refills for Schedule II (educational)."

        agent = PharmacyAgent(rag)
        result = agent.run("Can Schedule II be refilled?")
        assert result["agent"] is True
        assert result["intent"] == "dea"
        assert result["tool_used"] == "search_dea"
        assert "Schedule II" in result["answer"] or "refill" in result["answer"].lower()
        assert "classify→dea" in result["steps"]
        assert any(s.startswith("tool:") for s in result["steps"])

    def test_agent_empty_question(self) -> None:
        agent = PharmacyAgent(MagicMock())
        result = agent.run("  ")
        assert result["steps"] == ["reject:empty"]
