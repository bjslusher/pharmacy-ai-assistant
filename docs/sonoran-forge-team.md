# Sonoran Forge Dev Team — Operating Settings

**Project:** Pharmacy AI Assistant (and related Sonoran Forge assessment work)  
**Repo:** https://github.com/bjslusher/pharmacy-ai-assistant  
**Effective:** 2026-08-08

## Roles

| Role | Agent / person | Authority |
|------|----------------|-----------|
| **Tech lead / tester / git manager** | **Grok** | Sole authority to **pull from** and **push to** GitHub. Reviews all code, runs tests, merges or returns bugs. |
| **Developers** | Harper, Benjamin, Lucas (and human collaborators) | Write and improve code, tests, docs. Deliver content to Grok only. **No** direct GitHub read/write tool use for this repo unless Grok requests a one-off exception. |
| **Product owner** | Repo owner (`bjslusher`) | Final product direction, secrets, AWS credentials, assessment submission. |

## Workflow

1. **Write** — Team drafts files, fixes, and tests and sends them to Grok (chat / review channel).
2. **Review & test** — Grok consolidates, runs unit + integration tests, checks edge cases.
3. **Bug loop** — If Grok finds a bug, it is pushed **back to the team** with a clear failure description. Team fixes and resubmits.
4. **Ship** — Only Grok commits and pushes to `main` (or opens PRs if a branch workflow is later adopted).

```text
Team drafts → Grok tests → pass? → Grok pushes to GitHub
                    ↓ fail
              back to team with bug report
```

## Git rules (non-negotiable)

- **Grok is the only pusher and the only designated puller** for operational repo state used in decisions.
- Other agents must not call GitHub create/update/push/delete tools on this repository.
- If another agent needs file contents or tree status, they **ask Grok**; Grok disseminates the answer.

## Quality bar before push

- Unit tests: `tests/test_expand_query.py`, `tests/test_api_models.py`, `tests/test_rag_helpers.py`
- Integration tests: `tests/test_integration_api.py` (FastAPI TestClient + mocked RAG)
- CI green on `ci.yml` (backend tests, frontend build, Docker builds)
- No secrets committed; `.env` stays local / gitignored

## Communication

- Status and file content flow through Grok as tech lead.
- Assessment-facing claims (imprint ID, DEA rules) must keep educational disclaimers.

## Change control for these settings

Updates to this document require Grok review and a git push by Grok (or the human repo owner). Team members propose changes in draft form only.
