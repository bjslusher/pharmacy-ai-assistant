# Pharmacy AI Assistant

Educational full-stack RAG application tailored as a **pharmacy assistant** focused on:

- **Medication identification** (tablet imprint codes, NDC concepts)
- **DEA controlled-substance schedules** and pharmacist corresponding responsibility

Built for the AICO Assessment III requirements (RAG + Mem0, Docker, Terraform, GitHub Actions, documentation) with pharmacy-domain specialization.

> **Disclaimer:** This is an educational prototype only. It is **not** a clinical decision-support system, **not** a substitute for a licensed pharmacist, and **not** legal advice. Always verify against current DEA / FDA primary sources and professional judgment.

## Features

- Hybrid RAG over pharmacy knowledge base (Chroma + LangChain)
- Medication identification by imprint code / name / NDC concepts
- DEA Schedule I–V explanations and corresponding-responsibility guidance
- FastAPI backend + React (Vite) frontend
- Optional local Ollama or cloud LLM
- Optional Mem0 memory
- Docker Compose local stack
- Terraform AWS scaffolding (to be completed)
- GitHub Actions CI / deploy / destroy workflows (to be completed)

## Architecture

```
Frontend (React / Vite)  →  FastAPI Backend  →  LangChain RAG + Chroma
                                      ↓
                               Ollama / OpenAI (optional)
                                      ↓
                               Mem0 (optional memory)
```

- **Backend:** FastAPI, LangChain, Chroma vector store, pharmacy-specific prompts
- **Frontend:** Chat UI with dedicated Medication ID and DEA quick-prompt modes
- **Infra:** `docker-compose.yml` for local full stack; Terraform and Actions for cloud/CI

## Quick Start (Docker)

```bash
# 1. Clone
git clone https://github.com/bjslusher/pharmacy-ai-assistant.git
cd pharmacy-ai-assistant

# 2. Environment (optional)
cp backend/.env.example backend/.env
# Edit as needed (Ollama URL, Mem0 key, etc.)

# 3. Ensure Ollama models are available
#    ollama pull llama3
#    ollama pull nomic-embed-text

# 4. Start the stack
docker compose up --build
```

- Frontend: http://localhost:3000  
- Backend API docs: http://localhost:8000/docs  
- Health: http://localhost:8000/api/health  

## Key API Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/health` | Health + indexed document count |
| POST | `/api/chat` | General pharmacy RAG chat |
| POST | `/api/meds/identify` | Imprint / medication identification mode |
| POST | `/api/dea/query` | DEA schedules & corresponding-responsibility mode |

## Knowledge Base

Educational seed documents live in `backend/source_data/`:

| File | Content |
|------|---------|
| `common_controlled_imprints.txt` | Expanded common Schedule II / III / IV tablet imprint examples |
| Additional DEA schedule & corresponding-responsibility summaries | Add as needed |

**Imprint identification is limited to the educational examples in the seed data.** It is not a live commercial pill identifier. Unknown codes will be refused or answered with low confidence and a redirect to official tools.

## Official Sources (do not commit full PDFs)

### DEA – Controlled Substances & Pharmacy Practice
| Resource | Link |
|----------|------|
| Pharmacist's Manual (2022 PDF) | https://www.deadiversion.usdoj.gov/GDP/(DEA-DC-046R1)(EO-DEA154R1)_Pharmacist's_Manual_DEA.pdf |
| Controlled Substances by Drug Code | https://www.deadiversion.usdoj.gov/schedules/orangebook/d_cs_drugcode.pdf |
| eCFR 21 CFR Part 1308 (Schedules) | https://www.ecfr.gov/current/title-21/chapter-II/part-1308 |
| Drug Scheduling overview | https://www.dea.gov/drug-information/drug-scheduling |
| Publications & Manuals index | https://www.deadiversion.usdoj.gov/pubs/manuals/manuals.html |

### FDA – Medication Identification
| Resource | Link |
|----------|------|
| NDC Directory | https://www.fda.gov/drugs/drug-approvals-and-databases/national-drug-code-directory |
| Orange Book data files | https://www.fda.gov/drugs/drug-approvals-and-databases/orange-book-data-files |
| openFDA NDC API | https://open.fda.gov/apis/drug/ndc/ |
| DailyMed | https://dailymed.nlm.nih.gov/dailymed/ |

## Assessment Mapping (approximate)

| Area | Coverage |
|------|----------|
| RAG / LangChain / Mem0 | `backend/rag_service.py`, pharmacy prompts, Chroma, optional Mem0 |
| Docker | `backend/Dockerfile`, `frontend/Dockerfile`, `docker-compose.yml` |
| Terraform (AWS) | Scaffolding to be completed |
| CI/CD (GitHub Actions) | Workflows to be completed |
| Domain specialization | Pharmacy prompts, expanded imprint seed data, DEA educational focus |
| Documentation | This README + official source links |

## Important Limitations

- Imprint identification uses a **limited educational sample**, not a complete or live database.
- Controlled-substance answers must be verified against the current Pharmacist's Manual and 21 CFR 1308.
- No patient-specific data should be entered; this is a public educational demo.
- Counterfeit tablets are a known risk—visual identification alone is never sufficient for safety-critical decisions.

## License / Use

Educational assessment project. Government source material remains subject to its own terms; summaries in this repository are for learning only.
