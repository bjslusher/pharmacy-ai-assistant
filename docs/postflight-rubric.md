# Post-flight feature qualification (AICO Assessment III)

```bash
bash scripts/run.sh stop --yes          # teardown, then audit
bash scripts/run.sh postflight          # audit only
bash scripts/postflight.sh
```

## What each color means

| Color | Qualifying rule |
|-------|-----------------|
| **GREEN** | A **required feature** is implemented and part of the create → run → terminate path (not merely a file on disk). |
| **ORANGE** | A **bonus feature** that can earn extra rubric points if demonstrated. |
| **BLUE** | A feature a TA can verify **only by reading GitHub** (docs, workflows, diagrams) without starting the stack. |
| **RED** | A **required feature** is missing, incomplete, or not demonstrable after stop. |

Lines in the script are written as **features** (what the system does), not as stack inventory alone.

## Feature map by exam section

### 1. Mem0 + LangChain (25%)

| Feature (what qualifies) | Color |
|--------------------------|-------|
| Retrieve-then-generate RAG (split → embed → Chroma → retrieve → answer) | GREEN |
| Domain prompt templates (general / med ID / DEA) | GREEN |
| Mem0 semantic memory when `MEM0_API_KEY` is set | GREEN |
| Seed knowledge base as sole grounding corpus | GREEN |
| Medication imprint identification mode | GREEN |
| DEA schedule Q&A mode | GREEN |
| LangGraph workflows | ORANGE |
| LangSmith tracing | ORANGE |
| Custom autonomous agents | ORANGE |

### 2. Terraform (10%)

| Feature | Color |
|---------|-------|
| IaC apply/destroy of AWS resources | GREEN |
| Parameterized inputs + outputs | GREEN |
| S3 data/logs storage | GREEN |
| ALB public HTTP entry + path routing | GREEN |
| ASG + launch template elastic compute | GREEN |
| IAM instance profile (no keys on disk) | GREEN |
| EC2 user_data zero-touch bootstrap | GREEN |
| One-command cloud teardown on `stop` | GREEN |
| Free-tier-oriented sizing | ORANGE |
| Remote state / modules / workspaces | ORANGE |

### 3. GitHub Actions (30%)

| Feature | Color |
|---------|-------|
| CI on push/PR (lint + test + build) | BLUE + GREEN |
| Deploy/plan workflow | BLUE |
| Destroy workflow | ORANGE + BLUE |
| Containerized three-tier Compose stack | GREEN |
| Automated API regression tests | GREEN / ORANGE |
| Stress tests | ORANGE |
| Env-based secrets (no hard-coded keys) | GREEN |

### 4. Integrations (15%)

| Feature | Color |
|---------|-------|
| Local Ollama chat + embeddings | GREEN |
| Optional cloud LLM path | ORANGE |
| FastAPI HTTP API for the product | GREEN |
| React interactive client | GREEN |
| Browser-reachable UI (:3000 / ALB) | ORANGE |
| Streaming SSE answers | ORANGE |
| GPU detect + CPU fallback | ORANGE |
| Brand-pack polished UI | ORANGE |

### 5. Documentation (20%)

| Feature | Color |
|---------|-------|
| Repeatable operator runbook (README commands) | BLUE |
| Architecture diagram in repo | BLUE |
| Extra docs (AWS, errors, preflight) | BLUE |
| Rubric self-map | BLUE |
| Shell lifecycle automation | ORANGE / GREEN |
| Post-flight audit after destroy | ORANGE |

## Official deliverables as features

1. **Architecture communication** — BLUE  
2. **Repeatable setup instructions** — BLUE  
3. **CI/CD workflows visible on GitHub** — BLUE  
4. **Container build & orchestration** — GREEN  
5. **Automation that removes manual secret/setup steps** — GREEN / ORANGE  
