# Post-flight rubric map (AICO Assessment III)

Run after teardown:

```bash
bash scripts/run.sh stop --yes
# post-flight runs automatically at end of stop

# or standalone:
bash scripts/postflight.sh
```

## Color legend

| Tag | Meaning |
|-----|---------|
| **GREEN** | Required objective covered by build **and** clean terminate path |
| **ORANGE** | **Bonus** item (high visibility) |
| **BLUE** | Lives primarily as a **GitHub** artifact (README, workflows, docs) |
| **RED** | Missing or incomplete vs rubric |

## Exam outline → this repo

### 1. Mem0 + LangChain (25%)

| Item | Status | Where |
|------|--------|--------|
| LangChain-style prompts / chains | GREEN | `backend/prompts.py`, `rag_service.py` |
| RAG: load, split, embed, vector store | GREEN | `rag_service.py` + Chroma + `source_data/` |
| Mem0 API (optional key) | GREEN | `rag_service.py` (`MEM0_API_KEY`) |
| LangGraph / LangSmith / agents | ORANGE | Not required; not fully implemented |

### 2. Terraform (10%)

| Item | Status | Where |
|------|--------|--------|
| IaC for cloud resources | GREEN | `terraform/main.tf` (S3, IAM, ALB, ASG) |
| Variables / outputs | GREEN | `variables.tf`, `outputs.tf` |
| Destroy path | GREEN | `run.sh stop` → `terraform destroy` |
| Remote state / modules / workspaces | ORANGE | Local state OK for demo |
| Free-tier bias | ORANGE | `free-tier.tfvars` |

### 3. GitHub Actions (30%)

| Item | Status | Where |
|------|--------|--------|
| CI workflow | BLUE | `.github/workflows/ci.yml` |
| Deploy / plan workflow | BLUE | `.github/workflows/deploy.yml` |
| Destroy workflow | ORANGE + BLUE | `.github/workflows/destroy.yml` |
| Docker + Compose | GREEN | Dockerfiles, `docker-compose.yml` |
| Tests in CI | GREEN / ORANGE | pytest in `ci.yml` + `backend/tests/` |
| No hard-coded secrets | GREEN | `.env.example`, GH secrets for AWS |

### 4. Integrations (15%)

| Item | Status | Where |
|------|--------|--------|
| Ollama / optional cloud LLM | GREEN | `rag_service.py` |
| Backend API | GREEN | `backend/main.py` |
| Frontend | GREEN | `frontend/src/App.jsx` |
| Browser UI | ORANGE | localhost:3000 / ALB |

### 5. Documentation (20%)

| Item | Status | Where |
|------|--------|--------|
| Setup docs + commands | BLUE | `README.md` |
| Architecture diagram | BLUE | README mermaid |
| Extra docs (≥2) | BLUE | `docs/aws-deploy.md`, `error-handling.md`, … |
| Shell automation | ORANGE / GREEN | `scripts/run.sh`, `preflight.sh`, `postflight.sh` |
| All deliverables in GitHub | BLUE | this repository |

## Official deliverables

1. Architecture diagrams — **BLUE** (README + docs)
2. Terminal setup commands — **BLUE** (README)
3. GitHub Actions workflows — **BLUE**
4. Docker / Compose — **GREEN**
5. Automation scripts — **GREEN** / **ORANGE**
