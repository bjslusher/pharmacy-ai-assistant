"""
Stress / load tests against FastAPI TestClient with mocked RAG.

Goals:
- Concurrent chat / med-id / dea traffic does not crash the app
- Validation still rejects bad payloads under concurrent load
- Health remains available during burst traffic
- No cross-talk corruption of response shape

These tests do not require Ollama or Docker.
"""

from __future__ import annotations

import random
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from types import ModuleType
from unittest.mock import MagicMock, patch

import pytest

# ---------------------------------------------------------------------------
# Stub heavy deps before importing main
# ---------------------------------------------------------------------------


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

QUERIES = [
    "What is the DEA schedule for oxycodone?",
    "Can Schedule II prescriptions be refilled?",
    "Identify imprint M367",
    "Difference between Schedule III and IV",
    "Pharmacy recordkeeping for controlled substances",
    "Explain Schedule II prescribing rules",
]


def _make_mock_rag() -> MagicMock:
    rag = MagicMock()
    rag.document_count.return_value = 3
    rag.ensure_index = MagicMock()

    def _query(message: str = "", mode: str = "general", **_kwargs):
        # tiny deterministic delay to exercise concurrency
        time.sleep(random.uniform(0.001, 0.01))
        return {
            "answer": f"[{mode}] educational reply for: {message[:40]}",
            "sources": ["dea_schedules_overview.txt", "common_controlled_imprints.txt"],
        }

    rag.query.side_effect = _query
    rag.save_upload = MagicMock(
        side_effect=lambda name, content: Path("/tmp") / (name or "upload.txt")
    )
    rag.ingest_file = MagicMock(return_value=1)
    return rag


@pytest.fixture
def stress_client():
    mock_rag = _make_mock_rag()
    with (
        patch("rag_service.PharmacyRAG", return_value=mock_rag),
        patch("main.PharmacyRAG", return_value=mock_rag),
    ):
        import main as main_mod

        main_mod.rag = mock_rag
        from fastapi.testclient import TestClient

        with TestClient(main_mod.app) as c:
            main_mod.rag = mock_rag
            yield c, main_mod, mock_rag


def _post_chat(client, msg: str) -> tuple[int, dict]:
    r = client.post("/api/chat", json={"message": msg})
    try:
        body = r.json()
    except Exception:
        body = {}
    return r.status_code, body


def _post_med(client, msg: str) -> tuple[int, dict]:
    r = client.post("/api/meds/identify", json={"message": msg})
    try:
        body = r.json()
    except Exception:
        body = {}
    return r.status_code, body


def _post_dea(client, msg: str) -> tuple[int, dict]:
    r = client.post("/api/dea/query", json={"message": msg})
    try:
        body = r.json()
    except Exception:
        body = {}
    return r.status_code, body


class TestStressConcurrent:
    def test_concurrent_chat_burst(self, stress_client) -> None:
        client, _, mock_rag = stress_client
        n = 40
        with ThreadPoolExecutor(max_workers=16) as pool:
            futs = [
                pool.submit(_post_chat, client, QUERIES[i % len(QUERIES)])
                for i in range(n)
            ]
            results = [f.result() for f in as_completed(futs)]

        codes = [c for c, _ in results]
        assert all(c == 200 for c in codes), f"non-200 in burst: {set(codes)}"
        for _, body in results:
            assert "answer" in body
            assert body.get("mode") == "general"
            assert isinstance(body.get("sources"), list)
        assert mock_rag.query.call_count >= n

    def test_mixed_endpoints_concurrent(self, stress_client) -> None:
        client, _, _ = stress_client
        jobs = []
        with ThreadPoolExecutor(max_workers=20) as pool:
            for i in range(30):
                q = QUERIES[i % len(QUERIES)]
                if i % 3 == 0:
                    jobs.append(pool.submit(_post_med, client, q))
                elif i % 3 == 1:
                    jobs.append(pool.submit(_post_dea, client, q))
                else:
                    jobs.append(pool.submit(_post_chat, client, q))
            results = [f.result() for f in as_completed(jobs)]

        assert all(code == 200 for code, _ in results)
        modes = {body.get("mode") for _, body in results}
        assert "med_id" in modes
        assert "dea" in modes
        assert "general" in modes

    def test_health_during_load(self, stress_client) -> None:
        client, _, _ = stress_client
        health_codes: list[int] = []

        def hit_health() -> int:
            return client.get("/api/health").status_code

        def hit_chat() -> int:
            return client.post(
                "/api/chat", json={"message": "Schedule II refills?"}
            ).status_code

        with ThreadPoolExecutor(max_workers=12) as pool:
            futs = []
            for i in range(24):
                if i % 2 == 0:
                    futs.append(pool.submit(hit_health))
                else:
                    futs.append(pool.submit(hit_chat))
            for f in as_completed(futs):
                health_codes.append(f.result())

        assert all(c == 200 for c in health_codes)

    def test_validation_under_concurrency(self, stress_client) -> None:
        client, _, _ = stress_client

        def bad_payload() -> int:
            return client.post("/api/chat", json={"message": ""}).status_code

        def good_payload() -> int:
            return client.post(
                "/api/chat", json={"message": "What is Schedule III?"}
            ).status_code

        with ThreadPoolExecutor(max_workers=12) as pool:
            bad_futs = [pool.submit(bad_payload) for _ in range(15)]
            good_futs = [pool.submit(good_payload) for _ in range(15)]
            bad_codes = [f.result() for f in as_completed(bad_futs)]
            good_codes = [f.result() for f in as_completed(good_futs)]

        assert all(c == 422 for c in bad_codes)
        assert all(c == 200 for c in good_codes)

    def test_sequential_sustained_load(self, stress_client) -> None:
        """Many sequential requests — baseline latency smoke (mocked)."""
        client, _, mock_rag = stress_client
        start = time.perf_counter()
        for i in range(50):
            r = client.post("/api/chat", json={"message": QUERIES[i % len(QUERIES)]})
            assert r.status_code == 200
            assert "answer" in r.json()
        elapsed = time.perf_counter() - start
        # Mocked path should stay well under a few seconds even for 50 calls
        assert elapsed < 30.0, f"sequential 50 calls took {elapsed:.2f}s"
        assert mock_rag.query.call_count >= 50


class TestStressEdgeCases:
    def test_rapid_mode_switching(self, stress_client) -> None:
        client, _, _ = stress_client
        endpoints = [
            ("/api/chat", "general"),
            ("/api/meds/identify", "med_id"),
            ("/api/dea/query", "dea"),
        ]
        for i in range(18):
            path, expected_mode = endpoints[i % 3]
            r = client.post(path, json={"message": QUERIES[i % len(QUERIES)]})
            assert r.status_code == 200
            assert r.json()["mode"] == expected_mode

    def test_stats_and_health_spam(self, stress_client) -> None:
        client, _, _ = stress_client
        with ThreadPoolExecutor(max_workers=10) as pool:
            futs = []
            for _ in range(20):
                futs.append(pool.submit(lambda: client.get("/api/health").status_code))
                futs.append(pool.submit(lambda: client.get("/api/stats").status_code))
            codes = [f.result() for f in as_completed(futs)]
        assert all(c == 200 for c in codes)
