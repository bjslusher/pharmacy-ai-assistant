# Contributing — Sonoran Forge / Pharmacy AI Assistant

Please read **[docs/sonoran-forge-team.md](docs/sonoran-forge-team.md)** for team roles and process.

**Summary:** Grok is the sole git manager and tester. Developers draft code and send it for review; only Grok pushes to GitHub.

## Running tests locally

```bash
cd backend
pip install -r requirements.txt
pytest -q tests/test_expand_query.py tests/test_api_models.py tests/test_rag_helpers.py
pytest -q tests/test_integration_api.py
```

Integration tests fully mock the RAG service and do not require Ollama.
