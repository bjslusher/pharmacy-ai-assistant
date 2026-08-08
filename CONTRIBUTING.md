# Contributing — Pharmacy AI Assistant

## Running tests locally

```bash
cd backend
pip install -r requirements.txt
pytest -q tests/test_expand_query.py tests/test_api_models.py tests/test_rag_helpers.py
pytest -q tests/test_integration_api.py
```

Integration tests fully mock the RAG service and do not require Ollama.

## Lint

```bash
cd backend
pip install ruff
ruff check .
```

## Notes

- Do not commit secrets or `.env` files.
- Educational disclaimers must remain on medication/DEA answers.
- Prefer PRs against `main` with CI green (lint, tests, frontend build, Docker builds).
