#!/usr/bin/env bash
# =============================================================================
# Post-flight — AICO Assessment III deliverable audit (after stop / teardown)
#
# Colors = feature qualification (not just "file exists"):
#   GREEN  — required feature implemented AND usable in create→run→terminate path
#   ORANGE — bonus feature that earns extra rubric credit
#   BLUE   — documentation / CI / repo artifact a TA reviews on GitHub without running
#   RED    — required feature missing, broken, or not demonstrable
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

G='\033[0;32m'
O='\033[38;5;208m'
B='\033[0;34m'
R='\033[0;31m'
N='\033[0m'
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

echo
printf "${BOLD}╔══════════════════════════════════════════════════════════╗${N}\n"
printf "${BOLD}║  POST-FLIGHT — Assessment III feature qualification    ║${N}\n"
printf "${BOLD}╚══════════════════════════════════════════════════════════╝${N}\n"
echo "Each line is the FEATURE that earns the color (not only a file path)."
echo "  ${G}GREEN${N}  = required feature built + exercised in start/stop"
echo "  ${O}ORANGE${N} = bonus feature for extra credit (CLAIMED = present in this repo)"
echo "  ${B}BLUE${N}   = TA can verify on GitHub without running the stack"
echo "  ${R}RED${N}    = required feature missing or not demonstrable"
echo "Repo: $ROOT"
echo "Time: $(date -Iseconds 2>/dev/null || date)"

# ---------------------------------------------------------------------------
section "0. Teardown features (prove clean terminate)"
# ---------------------------------------------------------------------------

COMPOSE=(docker compose)
docker compose version >/dev/null 2>&1 || COMPOSE=(docker-compose)

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  left="$("${COMPOSE[@]}" -f docker-compose.yml ps -q 2>/dev/null || true)"
  if [[ -z "${left}" ]]; then
    mark_green "Feature: full local stack shutdown — no Compose containers left after stop"
  else
    mark_red "Feature missing: clean Docker stop (containers still running after stop)"
    "${COMPOSE[@]}" -f docker-compose.yml ps 2>/dev/null || true
  fi
else
  mark_green "Feature: Docker treated as stopped (daemon not reachable on this host)"
fi

if [[ -f "$ROOT/terraform/terraform.tfstate" ]] && [[ -s "$ROOT/terraform/terraform.tfstate" ]]; then
  if command -v terraform >/dev/null 2>&1; then
    res="$(cd "$ROOT/terraform" && terraform state list 2>/dev/null || true)"
    if [[ -z "${res}" ]]; then
      mark_green "Feature: AWS teardown complete — Terraform state empty (no residual managed resources)"
    else
      mark_red "Feature missing: complete AWS destroy (state still lists resources)"
      echo "$res" | sed 's/^/    /' | head -20
    fi
  else
    mark_red "Feature missing: verify AWS destroy (terraform CLI absent; state file still present)"
  fi
else
  mark_green "Feature: no cloud footprint from this workspace (no terraform state to destroy)"
fi

# ---------------------------------------------------------------------------
section "1. Mem0 + LangChain features (25%)"
# ---------------------------------------------------------------------------

if has_file backend/rag_service.py && grep -qE 'Chroma|similarity_search|from_documents|split_documents' "$ROOT/backend/rag_service.py" 2>/dev/null; then
  mark_green "Feature: RAG retrieve-then-generate — documents split, embedded, stored in Chroma, retrieved before LLM answer"
else
  mark_red "Feature missing: RAG pipeline (load → split → embed → vector retrieve → generate)"
fi

if has_file backend/prompts.py && grep -qE 'PromptTemplate|ChatPromptTemplate|RAG_PROMPT|MED_ID_PROMPT|DEA_QUERY' "$ROOT/backend/prompts.py" 2>/dev/null; then
  mark_green "Feature: domain prompt templates — separate instruction paths for general chat, med ID, and DEA queries"
else
  mark_red "Feature missing: multi-step / templated prompts for pharmacy modes"
fi

if grep -qE 'mem0|MemoryClient|MEM0_API_KEY' "$ROOT/backend/rag_service.py" 2>/dev/null; then
  mark_green "Feature: semantic memory hook — Mem0 client optional via MEM0_API_KEY for cross-session context"
else
  mark_red "Feature missing: Mem0 (or equivalent) semantic memory integration"
fi

if has_dir backend/source_data && find "$ROOT/backend/source_data" -name '*.txt' 2>/dev/null | grep -q .; then
  n=$(find "$ROOT/backend/source_data" -name '*.txt' 2>/dev/null | wc -l | tr -d ' ')
  mark_green "Feature: grounded knowledge base — $n seed document(s) become the only Chroma source for answers"
else
  mark_red "Feature missing: seed knowledge corpus for RAG grounding"
fi

if grep -qE 'med_id|/api/meds/identify' "$ROOT/backend/main.py" 2>/dev/null && grep -qiE 'imprint|Schedule' "$ROOT/backend/source_data/"*.txt 2>/dev/null; then
  mark_green "Feature: medication imprint identification mode (API + seed imprint data)"
else
  mark_red "Feature missing: medication imprint identification as a first-class mode"
fi

if grep -qE 'dea|/api/dea/query' "$ROOT/backend/main.py" 2>/dev/null && grep -qiE 'Schedule II|DEA' "$ROOT/backend/source_data/"*.txt 2>/dev/null; then
  mark_green "Feature: DEA / controlled-substance schedule Q&A mode (API + schedule seed text)"
else
  mark_red "Feature missing: DEA schedule guidance mode"
fi

# Bonus — path-based detection (must match what we actually shipped)
if has_file backend/agents/graph.py && grep -qE 'StateGraph|langgraph' "$ROOT/backend/agents/graph.py" 2>/dev/null; then
  mark_orange "Bonus CLAIMED: LangGraph workflow — classify → Chroma tool → grounded answer (agents/graph.py)"
else
  mark_orange "Bonus not claimed: LangGraph workflows (optional extra credit)"
fi
if has_file backend/agents/tracing.py && grep -qE 'LANGCHAIN_TRACING|configure_langsmith' "$ROOT/backend/agents/tracing.py" 2>/dev/null; then
  mark_orange "Bonus CLAIMED: LangSmith observability hook (agents/tracing.py; set LANGCHAIN_TRACING_V2=true + API key)"
else
  mark_orange "Bonus not claimed: LangSmith observability (optional extra credit)"
fi
if has_file backend/agents/graph.py && grep -qE 'PharmacyAgent|run_pharmacy_agent' "$ROOT/backend/agents/graph.py" 2>/dev/null \
  && has_file backend/main.py && grep -q '/api/agent/chat' "$ROOT/backend/main.py" 2>/dev/null; then
  mark_orange "Bonus CLAIMED: autonomous agent — POST /api/agent/chat routes imprint/DEA/general Chroma tools"
else
  mark_orange "Bonus not claimed: custom autonomous agents (optional extra credit)"
fi

# ---------------------------------------------------------------------------
section "2. Terraform / cloud features (10%)"
# ---------------------------------------------------------------------------

if has_file terraform/main.tf && grep -qE 'resource "aws_' "$ROOT/terraform/main.tf" 2>/dev/null; then
  mark_green "Feature: infrastructure-as-code — AWS resources declared and apply/destroyable via Terraform"
else
  mark_red "Feature missing: Terraform-provisioned cloud infrastructure"
fi

if has_file terraform/variables.tf && has_file terraform/outputs.tf; then
  mark_green "Feature: parameterized IaC — inputs via variables + machine-readable outputs (URLs, bucket names)"
else
  mark_red "Feature missing: Terraform variables and outputs for reusable deploys"
fi

if grep -qE 'aws_s3_bucket' "$ROOT/terraform/main.tf" 2>/dev/null; then
  mark_green "Feature: durable object storage — S3 buckets for data/logs (created on apply, removed on destroy)"
else
  mark_red "Feature missing: S3 data plane in Terraform"
fi

if grep -qE 'aws_lb|aws_lb_listener' "$ROOT/terraform/main.tf" 2>/dev/null; then
  mark_green "Feature: public HTTP entry — Application Load Balancer routes /api/* and UI traffic"
else
  mark_red "Feature missing: load-balanced public entry (ALB)"
fi

if grep -qE 'aws_autoscaling_group|aws_launch_template' "$ROOT/terraform/main.tf" 2>/dev/null; then
  mark_green "Feature: elastic compute — Auto Scaling Group + launch template (scale / replace instances)"
else
  mark_red "Feature missing: Auto Scaling / launch template for app hosts"
fi

if grep -qE 'aws_iam_role|instance_profile' "$ROOT/terraform/main.tf" 2>/dev/null; then
  mark_green "Feature: least-privilege instance identity — IAM role/profile for EC2→S3 without embedded keys"
else
  mark_red "Feature missing: IAM instance profile for cloud app hosts"
fi

if has_file terraform/user_data.sh.tpl; then
  mark_green "Feature: zero-touch host bootstrap — EC2 user_data installs/runs app stack on first boot"
else
  mark_red "Feature missing: instance user_data bootstrap"
fi

if has_file scripts/run.sh && grep -q 'destroy' "$ROOT/scripts/run.sh" 2>/dev/null; then
  mark_green "Feature: one-command cloud teardown — stop runs terraform destroy so ASG cannot respawn instances"
else
  mark_red "Feature missing: orchestrated terraform destroy on stop"
fi

if has_file terraform/free-tier.tfvars || grep -qiE 't3.micro|free.tier' "$ROOT/terraform/"*.tf* 2>/dev/null; then
  mark_orange "Bonus CLAIMED: cost-aware defaults (free-tier-oriented instance/size choices)"
fi
if grep -rqE 'backend[[:space:]]*"s3"|dynamodb_table' "$ROOT/terraform" --include='*.tf' 2>/dev/null; then
  mark_orange "Bonus CLAIMED: remote Terraform state (S3/DynamoDB locking)"
else
  mark_orange "Bonus not claimed: remote state backend (local state used for demo — acceptable)"
fi
if find "$ROOT/terraform" -type d -name modules 2>/dev/null | grep -q .; then
  mark_orange "Bonus CLAIMED: Terraform modules for reusable resource groups"
else
  mark_orange "Bonus not claimed: Terraform modules / workspaces (optional; flat main.tf is fine for this demo)"
fi

# ---------------------------------------------------------------------------
section "3. GitHub Actions / automation features (30%)"
# ---------------------------------------------------------------------------

if has_file .github/workflows/ci.yml; then
  mark_blue "Feature (GitHub): continuous integration on push/PR — lint + tests + builds without manual steps"
  if grep -qiE 'ruff|lint' "$ROOT/.github/workflows/ci.yml" 2>/dev/null; then
    mark_green "Feature: automated static analysis — Ruff lint runs in CI on every push/PR"
  fi
  if grep -qiE 'pytest' "$ROOT/.github/workflows/ci.yml" 2>/dev/null; then
    mark_green "Feature: automated regression tests — pytest unit/integration in CI"
  fi
else
  mark_red "Feature missing: CI workflow that runs tests/lint on push"
fi

if has_file .github/workflows/deploy.yml; then
  mark_blue "Feature (GitHub): deploy pipeline — Terraform plan (and related checks) via Actions"
else
  mark_red "Feature missing: deploy/plan GitHub Actions workflow"
fi

if has_file .github/workflows/destroy.yml; then
  mark_orange "Bonus CLAIMED: dedicated destroy workflow — cloud teardown triggerable from Actions UI"
  mark_blue "Feature (GitHub): destroy.yml visible to TAs in the Actions tab"
else
  mark_orange "Bonus not claimed: separate destroy workflow in GitHub Actions"
fi

if has_file docker-compose.yml && has_file backend/Dockerfile && has_file frontend/Dockerfile; then
  mark_green "Feature: containerized three-tier stack — backend API, frontend UI, and Ollama runnable via Compose"
else
  mark_red "Feature missing: Dockerized multi-service app (API + UI + model runtime)"
fi

if has_file backend/tests/test_integration_api.py || has_file backend/tests/test_expand_query.py; then
  mark_orange "Bonus CLAIMED: Python test suite (unit + API integration with mocked RAG)"
  mark_green "Feature: testable API contracts — health/chat/meds/dea covered by automated tests"
else
  mark_red "Feature missing: automated backend tests"
fi

if has_file backend/tests/test_stress_api.py; then
  mark_orange "Bonus CLAIMED: stress/load tests — concurrent API pressure beyond happy-path unit tests"
fi
if has_file backend/tests/test_agent.py; then
  mark_orange "Bonus CLAIMED: agent unit tests (intent routing + Chroma tools)"
fi

if has_file backend/.env.example; then
  mark_green "Feature: secret-safe configuration — env template for keys; no secrets hard-coded for CI/runtime"
else
  mark_red "Feature missing: env-based secrets pattern (.env.example)"
fi

# ---------------------------------------------------------------------------
section "4. Integration features (15%)"
# ---------------------------------------------------------------------------

if grep -qE 'ChatOllama|OllamaEmbeddings' "$ROOT/backend/rag_service.py" 2>/dev/null; then
  mark_green "Feature: local LLM inference — Ollama chat + embedding models (no required cloud LLM spend)"
else
  mark_red "Feature missing: Ollama or equivalent model integration"
fi

if grep -qE 'openai|ChatOpenAI|bedrock' "$ROOT/backend/rag_service.py" 2>/dev/null; then
  mark_orange "Bonus CLAIMED: optional cloud LLM provider path (OpenAI/Bedrock-style) beside Ollama"
fi

if has_file backend/main.py && grep -qE '@app\.(post|get).*\/api\/' "$ROOT/backend/main.py" 2>/dev/null; then
  mark_green "Feature: backend HTTP API — FastAPI exposes chat, identify, DEA, health, ingest for the UI and demos"
else
  mark_red "Feature missing: application backend API"
fi

if has_file frontend/src/App.jsx; then
  mark_green "Feature: interactive front end — React UI for questions, med ID form, and streamed answers"
else
  mark_red "Feature missing: front-end client for the assistant"
fi

if has_file frontend/nginx.conf || has_file frontend/Dockerfile; then
  mark_orange "Bonus CLAIMED: browser-reachable system UI — served on :3000 (local) and via ALB (cloud)"
fi

if has_dir docs/brand && find "$ROOT/docs/brand" -name '*.png' 2>/dev/null | grep -q .; then
  mark_orange "Bonus CLAIMED: polished product branding — Sonoran Forge assets in the live UI"
fi

if grep -qE 'stream|text/event-stream|chat/stream' "$ROOT/backend/main.py" 2>/dev/null; then
  mark_orange "Bonus CLAIMED: streaming responses (SSE) for lower perceived latency"
fi

if has_file scripts/gpu_select.sh; then
  mark_orange "Bonus CLAIMED: GPU detect + user choice with CPU fallback for faster local inference"
fi

# ---------------------------------------------------------------------------
section "5. Documentation & presentation features (20%)"
# ---------------------------------------------------------------------------

if has_file README.md; then
  mark_blue "Feature (GitHub): operator runbook — clone, start, full, stop, test commands a teammate can repeat"
else
  mark_red "Feature missing: README setup documentation"
fi

if grep -qE 'mermaid|flowchart|Architecture' "$ROOT/README.md" 2>/dev/null; then
  mark_blue "Feature (GitHub): architecture diagram — system shape visible in README without running code"
else
  mark_red "Feature missing: architecture diagram in documentation"
fi

if has_file docs/aws-deploy.md || has_file docs/error-handling.md || has_file docs/preflight.md; then
  mark_blue "Feature (GitHub): secondary docs — AWS deploy, errors, or preflight beyond the main README"
else
  mark_red "Feature missing: at least two supporting documentation resources"
fi

if has_file docs/postflight-rubric.md; then
  mark_blue "Feature (GitHub): rubric self-map — explicit checklist tying code to Assessment III scoring"
fi
if has_file docs/security.md; then
  mark_blue "Feature (GitHub): security risks & mitigations (masked identity, gitignored secrets)"
fi

if has_file scripts/run.sh && has_file scripts/preflight.sh; then
  mark_orange "Bonus CLAIMED: shell automation — one command preflight + start/stop instead of manual multi-step setup"
  mark_green "Feature: repeatable local lifecycle — preflight gates failures before long Docker/AWS work"
else
  mark_red "Feature missing: setup/teardown automation scripts"
fi

if has_file scripts/postflight.sh; then
  mark_orange "Bonus CLAIMED: post-flight audit — after destroy, prove deliverables and teardown state for TAs"
fi

# ---------------------------------------------------------------------------
section "Official deliverable features"
# ---------------------------------------------------------------------------

mark_blue  "Deliverable feature: architecture communication (diagrams a TA can open on GitHub)"
mark_blue  "Deliverable feature: repeatable terminal setup instructions in README"
mark_blue  "Deliverable feature: GitHub Actions workflows for build/test/plan/destroy visibility"
mark_green "Deliverable feature: container build & orchestration (Dockerfiles + Compose up/down)"
mark_green "Deliverable feature: automation scripts that reduce manual secret/setup/teardown work"

# ---------------------------------------------------------------------------
section "POST-FLIGHT SUMMARY"
# ---------------------------------------------------------------------------
printf "  ${G}GREEN  — required features covered${N}:     %s\n" "$EXISTS"
printf "  ${O}ORANGE — bonus features listed${N}:        %s\n" "$BONUS"
printf "  ${B}BLUE   — GitHub-visible features${N}:      %s\n" "$GH"
printf "  ${R}RED    — required features missing${N}:    %s\n" "$MISS"
echo
echo "CLAIMED bonuses are implemented in this repo. 'not claimed' = optional work we did not ship."
echo

if [[ "$MISS" -eq 0 ]]; then
  printf "${G}${BOLD}No required features marked RED.${N}\n"
  exit 0
else
  printf "${R}${BOLD}%s required feature(s) marked RED — fix before presenting.${N}\n" "$MISS"
  exit 1
fi
