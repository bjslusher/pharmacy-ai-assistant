"""Unit tests for FastAPI request/response models and validation edge cases."""

import pytest
from pydantic import BaseModel, Field, ValidationError, field_validator


class ChatRequest(BaseModel):
    message: str = Field(..., min_length=1, max_length=4000)
    user_id: str = Field(default="default-user")
    session_id: str | None = None
    mode: str = Field(default="general")

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
    sources: list[str] = []
    mode: str
    disclaimer: str = (
        "Educational/informational only. Not medical, legal, or pharmaceutical advice. "
        "Verify with licensed professionals and current official DEA/FDA sources."
    )


class HealthResponse(BaseModel):
    status: str
    documents_indexed: int
    llm_provider: str


class TestChatRequestValidation:
    def test_valid_minimal(self) -> None:
        r = ChatRequest(message="What is Schedule II?")
        assert r.mode == "general"
        assert r.user_id == "default-user"

    def test_empty_message_rejected(self) -> None:
        with pytest.raises(ValidationError):
            ChatRequest(message="")

    def test_whitespace_only_message_rejected(self) -> None:
        with pytest.raises(ValidationError):
            ChatRequest(message="   ")

    def test_message_too_long(self) -> None:
        with pytest.raises(ValidationError):
            ChatRequest(message="x" * 4001)

    def test_message_at_max_length(self) -> None:
        r = ChatRequest(message="x" * 4000)
        assert len(r.message) == 4000

    def test_mode_med_id(self) -> None:
        r = ChatRequest(message="M367", mode="med_id")
        assert r.mode == "med_id"

    def test_mode_dea(self) -> None:
        r = ChatRequest(message="refills", mode="dea")
        assert r.mode == "dea"

    def test_invalid_mode_rejected(self) -> None:
        with pytest.raises(ValidationError):
            ChatRequest(message="hi", mode="hacker")

    def test_custom_user_and_session(self) -> None:
        r = ChatRequest(message="hi", user_id="u1", session_id="s1")
        assert r.user_id == "u1"
        assert r.session_id == "s1"


class TestChatResponse:
    def test_disclaimer_always_present(self) -> None:
        r = ChatResponse(answer="Schedule II", mode="dea")
        assert "Educational" in r.disclaimer
        assert r.sources == []

    def test_sources_list(self) -> None:
        r = ChatResponse(answer="ok", mode="general", sources=["a.txt", "b.txt"])
        assert len(r.sources) == 2


class TestHealthResponse:
    def test_zero_docs(self) -> None:
        h = HealthResponse(status="healthy", documents_indexed=0, llm_provider="ollama")
        assert h.documents_indexed == 0
