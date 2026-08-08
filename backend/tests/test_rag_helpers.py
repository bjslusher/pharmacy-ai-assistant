"""Lightweight tests for RAG helper edge cases without requiring Ollama."""
import os
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest


class TestDocumentCountSafe:
    def test_none_vectorstore_returns_zero(self):
        from rag_service import PharmacyRAG

        with patch.object(PharmacyRAG, "_build_embeddings", return_value=MagicMock()), \
             patch.object(PharmacyRAG, "_build_llm", return_value=MagicMock()), \
             patch.object(PharmacyRAG, "_init_mem0", return_value=None):
            rag = PharmacyRAG()
            rag.vectorstore = None
            assert rag.document_count() == 0

    def test_vectorstore_count_exception_returns_zero(self):
        from rag_service import PharmacyRAG

        with patch.object(PharmacyRAG, "_build_embeddings", return_value=MagicMock()), \
             patch.object(PharmacyRAG, "_build_llm", return_value=MagicMock()), \
             patch.object(PharmacyRAG, "_init_mem0", return_value=None):
            rag = PharmacyRAG()
            vs = MagicMock()
            vs._collection.count.side_effect = RuntimeError("broken")
            rag.vectorstore = vs
            assert rag.document_count() == 0


class TestSaveUpload:
    def test_save_upload_writes_bytes(self, tmp_path):
        from rag_service import PharmacyRAG

        with patch.object(PharmacyRAG, "_build_embeddings", return_value=MagicMock()), \
             patch.object(PharmacyRAG, "_build_llm", return_value=MagicMock()), \
             patch.object(PharmacyRAG, "_init_mem0", return_value=None):
            rag = PharmacyRAG()
            os.environ["DATA_PATH"] = str(tmp_path)
            path = rag.save_upload("note.txt", b"Schedule II educational note")
            assert path.exists()
            assert path.read_text() == "Schedule II educational note"
            os.environ.pop("DATA_PATH", None)


class TestIngestEmpty:
    def test_ingest_empty_txt_returns_zero(self, tmp_path):
        from rag_service import PharmacyRAG

        with patch.object(PharmacyRAG, "_build_embeddings", return_value=MagicMock()), \
             patch.object(PharmacyRAG, "_build_llm", return_value=MagicMock()), \
             patch.object(PharmacyRAG, "_init_mem0", return_value=None):
            rag = PharmacyRAG()
            rag.vectorstore = MagicMock()
            empty = tmp_path / "empty.txt"
            empty.write_text("")
            assert rag.ingest_file(empty) == 0
