"""Optional LangSmith observability — enable with LANGCHAIN_TRACING_V2=true."""

from __future__ import annotations

import logging
import os

logger = logging.getLogger("pharmacy-agent")


def configure_langsmith() -> dict:
    """
    Turn on LangSmith if env is set. Safe no-op when unset.

    Env:
      LANGCHAIN_TRACING_V2=true
      LANGCHAIN_API_KEY=...
      LANGCHAIN_PROJECT=pharmacy-ai-assistant  (optional)
    """
    enabled = os.getenv("LANGCHAIN_TRACING_V2", "").lower() in {"1", "true", "yes"}
    key = os.getenv("LANGCHAIN_API_KEY") or os.getenv("LANGSMITH_API_KEY")
    project = os.getenv("LANGCHAIN_PROJECT", "pharmacy-ai-assistant")

    status = {
        "langsmith_enabled": bool(enabled and key),
        "langsmith_project": project if enabled else None,
        "hint": None,
    }

    if enabled and not key:
        status["hint"] = "LANGCHAIN_TRACING_V2 set but no LANGCHAIN_API_KEY — tracing skipped"
        logger.warning(status["hint"])
        return status

    if status["langsmith_enabled"]:
        os.environ.setdefault("LANGCHAIN_TRACING_V2", "true")
        os.environ.setdefault("LANGCHAIN_PROJECT", project)
        logger.info("LangSmith tracing enabled project=%s", project)
    else:
        logger.debug("LangSmith tracing off (set LANGCHAIN_TRACING_V2=true + API key to enable)")

    return status
