"""
Integration tests: FastAPI TestClient + fully mocked PharmacyRAG.
Covers /api/chat, /api/meds/identify, /api/dea/query, health, validation, 503, ingest.
"""

from __future__ import annotations

import sys
from pathlib import Path
from types import ModuleType
from unittest.mock import MagicMock, patch

import pytest


def _stub(name: str) -> ModuleType:
    if name not in sys.modules:
        sys.modules[name] = ModuleType(name)
    return sys.modules[name]


for mod_name in [
    "langchain_core",
    "langchain_core.documents",
    "langchain_core.prompts",
    "langchain_core.output_parsers",
    "langchain_core.runnables",
    "langchain_text_splitters",
    "langchain_community",
    "langchain_community.vectorstores",
    "langchain_ollama",
    "langchain_openai",
    "chromadb",
    "mem0",
    "pypdf",
    "langgraph",
    "langgraph.graph",
]:
    _stub(mod_name)

sys.modules["langchain_core.prompts"].ChatPromptTemplate = MagicMock()
sys.modules["langchain_core.prompts"].PromptTemplate = MagicMock()
sys.modules["langchain_core.prompts"].PromptTemplate.from_template = MagicMock(
    return_value=MagicMock()
)
sys.modules["langchain_core.prompts"].ChatPromptTemplate.from_messages = MagicMock(
    return_value=MagicMock()
)
sys.modules["langchain_core.documents"].Document = MagicMock()
sys.modules["langchain_core.output_parsers"].StrOutputParser = MagicMock()
sys.modules["langchain_core.runnables"].RunnablePassthrough = MagicMock()
sys.modules["langchain_text_splitters"].RecursiveCharacterTextSplitter = MagicMock()
sys.modules["langchain_community.vectorstores"].Chroma = MagicMock()
sys.modules["langchain_ollama"].ChatOllama = MagicMock()
sys.modules["langchain_ollama"].OllamaEmbeddings = MagicMock()

BACKEND = Path(__file__).resolve().parent.parent
if str(BACKEND) not in sys.path:
    sys.path.insert(0, str(BACKEND))


def _make_mock_rag(
    answer: str = "Educational answer about Schedule II.",
    sources: list[str] | None = None,
):
    rag = MagicMock()
    rag.document_count.return_value = 3
    rag.ensure_index = MagicMock()
    rag.index_status.return_value = {
        "path": "/tmp/chroma_db",
        "documents_indexed": 3,
        "sources": ["dea_schedules_overview.txt", "common_controlled_imprints.txt"],
        "embedding_model": "nomic-embed-text",
        "collection": "pharmacy_docs",
        "ready": True,
    }
    rag.query.return_value = {
        "answer": answer,
        "sources": sources if sources is not None else ["dea_schedules_overview.txt"],
    }
    rag.save_upload = MagicMock(
        side_effect=lambda name, content: Path("/tmp") / (name or "upload.txt")
    )
    rag.ingest_file = MagicMock(return_value=2)
    return rag


@pytest.fixture
def mock_rag():
    return _make_mock_rag()


@pytest.fixture
def client(mock_rag):
    with (
        patch("rag_service.PharmacyRAG", return_value=mock_rag),
        patch("main.PharmacyRAG", return_value=mock_rag),
    ):
        import main as main_mod

        main_mod.rag = mock_rag
        from fastapi.testclient import TestClient

        with TestClient(main_mod.app) as c:
            main_mod.rag = mock_rag
            yield c, main_mod


class TestHealth:
    def test_health_ok(self, client, mock_rag) -> None:
        c, _ = client
        r = c.get("/health")
        assert r.status_code == 200
        data = r.json()
        assert data["status"] == "healthy"
        assert data["documents_indexed"] == 3
        assert data.get("chroma") is None or isinstance(data.get("chroma"), dict)

    def test_api_health_alias(self, client) -> None:
        c, _ = client
        r = c.get("/api/health")
        assert r.status_code == 200


class TestValidation:
    def test_chat_blank_message_422(self, client) -> None:
        c, _ = client
        r = c.post("/api/chat", json={"message": "   "})
        assert r.status_code == 422

    def test_chat_empty_message_422(self, client) -> None:
        c, _ = client
        r = c.post("/api/chat", json={"message": ""})
        assert r.status_code == 422

    def test_chat_bad_mode_422(self, client) -> None:
        c, _ = client
        r = c.post("/api/chat", json={"message": "hello", "mode": "not-a-mode"})
        assert r.status_code == 422


class TestChatEndpoints:
    def test_chat_ok(self, client, mock_rag) -> None:
        c, main_mod = client
        main_mod.rag = mock_rag
        r = c.post("/api/chat", json={"message": "What is Schedule II?"})
        assert r.status_code == 200
        data = r.json()
        assert "answer" in data
        assert data["mode"] == "general"

    def test_meds_identify_forces_mode(self, client, mock_rag) -> None:
        c, main_mod = client
        main_mod.rag = mock_rag
        r = c.post("/api/meds/identify", json={"message": "imprint M367"})
        assert r.status_code == 200
        assert r.json()["mode"] == "med_id"

    def test_dea_query_forces_mode(self, client, mock_rag) -> None:
        c, main_mod = client
        main_mod.rag = mock_rag
        r = c.post("/api/dea/query", json={"message": "Schedule II refills"})
        assert r.status_code == 200
        assert r.json()["mode"] == "dea"

    def test_chat_sources_returned(self, client, mock_rag) -> None:
        c, main_mod = client
        main_mod.rag = mock_rag
        mock_rag.query.return_value = {
            "answer": "Educational (Schedule II may not be refilled).",
            "sources": [
                "dea_schedules_overview.txt",
                "pharmacist_responsibilities.txt",
            ],
        }
        r = c.post("/api/dea/query", json={"message": "Schedule II refills"})
        assert r.status_code == 200
        assert len(r.json()["sources"]) == 2


class TestRagNotReady:
    """When RAG is down and retry init also fails, endpoints return 503."""

    def test_chat_503_when_rag_none(self, client) -> None:
        c, main_mod = client
        main_mod.rag = None
        with patch.object(main_mod, "_init_rag", side_effect=RuntimeError("ollama down")):
            r = c.post("/api/chat", json={"message": "hello"})
        assert r.status_code == 503

    def test_stats_503_when_rag_none(self, client) -> None:
        c, main_mod = client
        main_mod.rag = None
        with patch.object(main_mod, "_init_rag", side_effect=RuntimeError("ollama down")):
            r = c.get("/api/stats")
        assert r.status_code == 503


class TestStatsAndIngest:
    def test_stats_ok(self, client, mock_rag) -> None:
        c, main_mod = client
        main_mod.rag = mock_rag
        r = c.get("/api/stats")
        assert r.status_code == 200
        assert r.json()["documents"] == 3

    def test_ingest_empty_file_400(self, client, mock_rag) -> None:
        c, main_mod = client
        main_mod.rag = mock_rag
        r = c.post("/api/ingest", files={"file": ("empty.txt", b"", "text/plain")})
        assert r.status_code == 400

    def test_ingest_ok(self, client, mock_rag) -> None:
        c, main_mod = client
        main_mod.rag = mock_rag
        r = c.post(
            "/api/ingest",
            files={"file": ("note.txt", b"Schedule II educational text", "text/plain")},
        )
        assert r.status_code == 200
        assert r.json()["status"] == "ok"
        assert r.json()["chunks_added"] == 2


class TestQueryError:
    def test_chat_500_on_rag_exception(self, client, mock_rag) -> None:
        c, main_mod = client
        main_mod.rag = mock_rag
        mock_rag.query.side_effect = RuntimeError("boom")
        r = c.post("/api/chat", json={"message": "Schedule II"})
        assert r.status_code == 500
        assert "Query failed" in r.json()["detail"]
