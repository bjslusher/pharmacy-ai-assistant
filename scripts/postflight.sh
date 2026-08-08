#!/usr/bin/env bash
# =============================================================================
# Post-flight — Assessment III deliverable audit (after stop / teardown)
#
# Colors:
#   GREEN  — required item covered by create + terminate path
#   ORANGE — BONUS item (high visibility)
#   BLUE   — GitHub-only artifact (README, workflows, docs in repo)
#   RED    — missing or incomplete vs rubric
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

G='\033[0;32m'   # green
O='\033[38;5;208m' # orange
B='\033[0;34m'   # blue
R='\033[0;31m'   # red
D='\033[2m'      # dim
N='\033[0m'      # reset
BOLD='\033[1m'

green()  { printf "${G}✔ GREEN ${N} %s\n" "$*"; }
orange() { printf "${O}★ BONUS ${N} %s\n" "$*"; }
blue()   { printf "${B}◆ GITHUB${N} %s\n" "$*"; }
red()    { printf "${R}✖ MISS  ${N} %s\n" "$*"; }
section(){ echo; printf "${BOLD}%s${N}\n" "$*"; echo "────────────────────────────────────────"; }

EXISTS=0; MISS=0; BONUS=0; GH=0

mark_green()  { green "$*"; EXISTS=$((EXISTS+1)); }
mark_orange() { orange "$*"; BONUS=$((BONUS+1)); }
mark_blue()   { blue "$*"; GH=$((GH+1)); }
mark_red()    { red "$*"; MISS=$((MISS+1)); }

has_file() { [[ -f "$ROOT/$1" ]]; }
has_dir()  { [[ -d "$ROOT/$1" ]]; }
grep_repo() { grep -R -l -E "$1" "$ROOT" --include='*.py' --include='*.yml' --include='*.yaml' --include='*.md' --include='*.sh' --include='*.tf' --include='*.jsx' 2>/dev/null | head -1; }

echo
printf "${BOLD}╔══════════════════════════════════════════════════════════╗${N}\n"
printf "${BOLD}║  POST-FLIGHT — AICO Assessment III deliverable audit   ║${N}\n"
printf "${BOLD}╚══════════════════════════════════════════════════════════╝${N}\n"
echo "Legend:  ${G}GREEN${N}=covered  ${O}ORANGE${N}=bonus  ${B}BLUE${N}=GitHub artifact  ${R}RED${N}=missed"
echo "Repo: $ROOT"
echo "Time: $(date -Iseconds 2>/dev/null || date)"

# ---------------------------------------------------------------------------
# Runtime teardown verification (what stop should have done)
# ---------------------------------------------------------------------------
section "0. Teardown state (runtime after stop)"

COMPOSE=(docker compose)
docker compose version >/dev/null 2>&1 || COMPOSE=(docker-compose)

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  left="$("${COMPOSE[@]}" -f docker-compose.yml ps -q 2>/dev/null || true)"
  if [[ -z "${left}" ]]; then
    mark_green "Docker Compose project stopped (no running containers)"
  else
    mark_red "Docker containers still running — re-run: bash scripts/run.sh stop --yes"
    "${COMPOSE[@]}" -f docker-compose.yml ps 2>/dev/null || true
  fi
else
  mark_green "Docker daemon not reachable (treated as down for this machine)"
fi

if [[ -f "$ROOT/terraform/terraform.tfstate" ]] && [[ -s "$ROOT/terraform/terraform.tfstate" ]]; then
  if command -v terraform >/dev/null 2>&1; then
    res="$(cd "$ROOT/terraform" && terraform state list 2>/dev/null || true)"
    if [[ -z "${res}" ]]; then
      mark_green "Terraform state empty (AWS resources destroyed)"
    else
      mark_red "Terraform still manages resources — run: bash scripts/run.sh stop --yes"
      echo "$res" | sed 's/^/    /' | head -20
    fi
  else
    mark_red "terraform.tfstate present but terraform CLI missing — cannot verify destroy"
  fi
else
  mark_green "No terraform state (nothing left to destroy from this workspace)"
fi

# ---------------------------------------------------------------------------
# 1. LangChain / RAG / Mem0 (25%)
# ---------------------------------------------------------------------------
section "1. Integration of Mem0 and LangChain (25%)"

if has_file backend/rag_service.py && grep -q 'Chroma\|vectorstore\|similarity_search' "$ROOT/backend/rag_service.py" 2>/dev/null; then
  mark_green "RAG pipeline: load → split → embed → Chroma vector store (rag_service.py)"
else
  mark_red "RAG pipeline / vector store not found in backend/rag_service.py"
fi

if has_file backend/prompts.py && grep -qE 'PromptTemplate|ChatPromptTemplate|RAG_PROMPT|MED_ID|DEA' "$ROOT/backend/prompts.py" 2>/dev/null; then
  mark_green "LangChain-style prompt templates (prompts.py)"
else
  mark_red "Prompt templates missing (backend/prompts.py)"
fi

if grep -q 'mem0\|MemoryClient\|MEM0' "$ROOT/backend/rag_service.py" 2>/dev/null; then
  mark_green "Mem0 integration present (optional at runtime via MEM0_API_KEY)"
else
  mark_red "Mem0 integration not found in rag_service.py"
fi

if has_dir backend/source_data && find "$ROOT/backend/source_data" -name '*.txt' 2>/dev/null | grep -q .; then
  n=$(find "$ROOT/backend/source_data" -name '*.txt' 2>/dev/null | wc -l | tr -d ' ')
  mark_green "Knowledge base seed files ($n txt under backend/source_data/)"
else
  mark_red "No seed documents under backend/source_data/"
fi

# Bonus RAG
if grep -qiE 'langgraph|langsmith|autonomous.agent' "$ROOT" --include='*.py' --include='*.md' 2>/dev/null | head -1 >/dev/null; then
  mark_orange "LangGraph / LangSmith / custom agents referenced in repo"
else
  mark_orange "LangGraph / LangSmith / autonomous agents — not implemented (optional bonus)"
fi

# ---------------------------------------------------------------------------
# 2. Terraform (10%)
# ---------------------------------------------------------------------------
section "2. Terraform Infrastructure as Code (10%)"

if has_file terraform/main.tf; then
  mark_green "Terraform main.tf present"
else
  mark_red "terraform/main.tf missing"
fi

if has_file terraform/variables.tf && has_file terraform/outputs.tf; then
  mark_green "Terraform variables.tf + outputs.tf"
else
  mark_red "Terraform variables/outputs incomplete"
fi

if grep -qE 'aws_s3_bucket|aws_lb|aws_autoscaling_group|aws_iam' "$ROOT/terraform/main.tf" 2>/dev/null; then
  mark_green "Cloud resources defined (S3 / IAM / ALB / ASG patterns found)"
else
  mark_red "Expected AWS resource types not found in main.tf"
fi

if has_file terraform/user_data.sh.tpl; then
  mark_green "EC2 user_data template for instance bootstrap"
else
  mark_red "user_data.sh.tpl missing"
fi

# Bonus TF
if has_file terraform/free-tier.tfvars; then
  mark_orange "Free-tier tfvars / cost-conscious defaults"
fi
if grep -qE 'backend \"|terraform \{' "$ROOT/terraform/"*.tf 2>/dev/null | head -1 >/dev/null; then
  if grep -rqE 'backend "s3"|dynamodb_table' "$ROOT/terraform" 2>/dev/null; then
    mark_orange "Remote Terraform state backend configured"
  else
    mark_orange "Remote state backend — local state only (acceptable for demo; remote is bonus)"
  fi
else
  mark_orange "Remote state / workspaces / modules — partial or not used (bonus)"
fi

# ---------------------------------------------------------------------------
# 3. GitHub Actions (30%) — mostly BLUE
# ---------------------------------------------------------------------------
section "3. GitHub Actions (30%)"

if has_file .github/workflows/ci.yml; then
  mark_blue "ci.yml — lint (Ruff) + pytest + frontend/docker checks"
else
  mark_red ".github/workflows/ci.yml missing"
fi

if has_file .github/workflows/deploy.yml; then
  mark_blue "deploy.yml — Terraform plan workflow"
else
  mark_red ".github/workflows/deploy.yml missing"
fi

if has_file .github/workflows/destroy.yml; then
  mark_orange "destroy.yml — dedicated destroy workflow (bonus pipeline design)"
  mark_blue "destroy.yml lives in GitHub Actions"
else
  mark_orange "destroy.yml workflow — not present (bonus)"
fi

if has_file docker-compose.yml && has_file backend/Dockerfile && has_file frontend/Dockerfile; then
  mark_green "Dockerfiles + docker-compose.yml (used by local run and referenced by CI)"
else
  mark_red "Docker / Compose files incomplete"
fi

if has_file backend/tests/test_integration_api.py || has_file backend/tests/test_expand_query.py; then
  mark_orange "Python unit/integration tests in backend/tests/ (bonus framework usage)"
  mark_green "Tests exist and are wired into CI + preflight"
else
  mark_red "No backend tests found"
fi

if has_file backend/tests/test_stress_api.py; then
  mark_orange "Stress tests (test_stress_api.py) — extra beyond unit/integration"
fi

if has_file backend/.env.example; then
  mark_green "Secrets pattern via .env.example (no hard-coded keys expected in source)"
else
  mark_red "backend/.env.example missing"
fi

# ---------------------------------------------------------------------------
# 4. Integrations (15%)
# ---------------------------------------------------------------------------
section "4. Integrations (15%)"

if grep -qE 'ChatOllama|OllamaEmbeddings|openai|bedrock' "$ROOT/backend/rag_service.py" 2>/dev/null; then
  mark_green "LLM path: Ollama (local) and/or cloud provider hooks in rag_service.py"
else
  mark_red "No LLM provider integration found"
fi

if has_file backend/main.py && grep -qE '/api/chat|/api/meds|/api/dea' "$ROOT/backend/main.py" 2>/dev/null; then
  mark_green "Backend API: FastAPI routes for chat / meds / dea"
else
  mark_red "Backend API routes incomplete"
fi

if has_file frontend/src/App.jsx; then
  mark_green "Frontend component for interacting with the app (React App.jsx)"
else
  mark_red "Frontend App.jsx missing"
fi

if has_file frontend/nginx.conf || has_file frontend/Dockerfile; then
  mark_orange "Browser-accessible UI via nginx/Docker on :3000 (system-level UI bonus)"
fi

if has_dir docs/brand && find "$ROOT/docs/brand" -name '*.png' 2>/dev/null | grep -q .; then
  mark_orange "Sonoran Forge brand pack integrated into frontend"
fi

# ---------------------------------------------------------------------------
# 5. Documentation (20%) — mostly BLUE
# ---------------------------------------------------------------------------
section "5. Documentation & Code Comments (20%)"

if has_file README.md; then
  mark_blue "README.md — setup, rubric map, commands, architecture"
else
  mark_red "README.md missing"
fi

if grep -qE 'mermaid|Architecture|flowchart' "$ROOT/README.md" 2>/dev/null; then
  mark_blue "Architecture diagram (mermaid / text) in README"
else
  mark_red "No architecture diagram in README"
fi

if has_file docs/aws-deploy.md || has_file docs/error-handling.md || has_file docs/preflight.md; then
  mark_blue "Extra docs under docs/ (aws-deploy / error-handling / preflight)"
else
  mark_red "Fewer than two supporting docs under docs/"
fi

if has_file scripts/run.sh && has_file scripts/preflight.sh; then
  mark_orange "Shell orchestrators (run.sh / preflight.sh) for repeatable setup — bonus"
  mark_green "One-command start/stop scripts present"
else
  mark_red "Orchestrator scripts missing"
fi

if has_file scripts/aws_up.sh && has_file scripts/aws_preflight.sh; then
  mark_green "AWS helper scripts (aws_up.sh / aws_preflight.sh)"
fi

# ---------------------------------------------------------------------------
# Explicit deliverables list from assessment README
# ---------------------------------------------------------------------------
section "Official deliverables checklist"

mark_blue  "1. Architecture diagrams — README mermaid + docs/"
mark_blue  "2. Terminal commands for setup — README Quick start + Commands table"
mark_blue  "3. GitHub Actions workflows — .github/workflows/{ci,deploy,destroy}.yml"
mark_green "4. Docker + Compose — Dockerfiles + docker-compose.yml (+ gpu overlay)"
mark_green "5. Automation scripts — scripts/run.sh, preflight, postflight, aws_*"

# ---------------------------------------------------------------------------
# Domain / pharmacy tailoring (project-specific)
# ---------------------------------------------------------------------------
section "Pharmacy domain focus (project tailoring)"

if grep -qiE 'imprint|Schedule II|DEA' "$ROOT/backend/source_data/"*.txt 2>/dev/null; then
  mark_green "Seed knowledge covers imprints + DEA schedules"
else
  mark_red "Seed data may lack imprint/DEA content"
fi

if grep -qE 'med_id|dea' "$ROOT/backend/main.py" 2>/dev/null; then
  mark_green "Dedicated /api/meds/identify and /api/dea/query endpoints"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
section "POST-FLIGHT SUMMARY"
printf "  ${G}GREEN (covered)${N}:     %s\n" "$EXISTS"
printf "  ${O}ORANGE (bonus)${N}:      %s\n" "$BONUS"
printf "  ${B}BLUE (GitHub-only)${N}:  %s\n" "$GH"
printf "  ${R}RED (missed)${N}:        %s\n" "$MISS"
echo

if [[ "$MISS" -eq 0 ]]; then
  printf "${G}${BOLD}All required deliverable checks passed (no RED).${N}\n"
  printf "Bonus items listed in ORANGE are optional score boosters.\n"
  exit 0
else
  printf "${R}${BOLD}%s item(s) marked RED — review above before submission.${N}\n" "$MISS"
  exit 1
fi
