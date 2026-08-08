#!/usr/bin/env bash
# Pharmacy AI Assistant orchestrator
# Order matters: Ollama up → pull models → backend (Chroma needs nomic-embed-text)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
# shellcheck disable=SC1091
source "$ROOT/scripts/status_ui.sh"

COMPOSE_BIN=(docker compose)
if ! docker compose version >/dev/null 2>&1; then
  if command -v docker-compose >/dev/null 2>&1; then COMPOSE_BIN=(docker-compose); else COMPOSE_BIN=(); fi
fi
COMPOSE=()
OLLAMA_MODEL="${OLLAMA_MODEL:-llama3.2:3b}"
OLLAMA_EMBED_MODEL="${OLLAMA_EMBED_MODEL:-nomic-embed-text}"
FRONTEND_URL="${FRONTEND_URL:-http://localhost:3000}"
BACKEND_URL="${BACKEND_URL:-http://localhost:8000}"
HEALTH_URL="${HEALTH_URL:-http://localhost:8000/api/health}"
OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"
FULL_YES=0
ACTIVE_ACCEL="cpu"

for arg in "$@"; do case "$arg" in --yes|-y) FULL_YES=1 ;; esac; done
export FULL_YES

run_preflight() {
  local mode="${1:-local}"
  [[ -f "$ROOT/scripts/preflight.sh" ]] || { ui_fail "scripts/preflight.sh missing"; exit 1; }
  FULL_YES="$FULL_YES" RUN_FULL_YES="${RUN_FULL_YES:-$FULL_YES}" bash "$ROOT/scripts/preflight.sh" "$mode"
}

run_postflight() {
  ui_section "Post-flight — Assessment III deliverable audit"
  if [[ -f "$ROOT/scripts/postflight.sh" ]]; then
    bash "$ROOT/scripts/postflight.sh" || true
  else
    ui_warn "scripts/postflight.sh missing"
  fi
}

configure_compose() {
  local pref="cpu"
  [[ -f "$ROOT/.gpu_preference" ]] && pref="$(tr -d '[:space:]' < "$ROOT/.gpu_preference" | tr '[:upper:]' '[:lower:]')"
  [[ -n "${GPU_PREFERENCE:-}" ]] && pref="$(echo "$GPU_PREFERENCE" | tr '[:upper:]' '[:lower:]')"
  [[ ${#COMPOSE_BIN[@]} -gt 0 ]] || return 1
  if [[ "$pref" == "gpu" && -f "$ROOT/docker-compose.gpu.yml" ]]; then
    COMPOSE=("${COMPOSE_BIN[@]}" -f docker-compose.yml -f docker-compose.gpu.yml)
    ACTIVE_ACCEL="gpu"; ui_ok "Compose mode: GPU primary"
  else
    COMPOSE=("${COMPOSE_BIN[@]}" -f docker-compose.yml)
    ACTIVE_ACCEL="cpu"; ui_ok "Compose mode: CPU"
  fi
}

ensure_env() {
  if [[ ! -f backend/.env ]]; then
    if [[ -f backend/.env.example ]]; then cp backend/.env.example backend/.env; ui_ok "backend/.env from example"
    else echo "LLM_PROVIDER=ollama" > backend/.env; ui_ok "backend/.env minimal"; fi
  else ui_ok "backend/.env present"; fi
}

wait_http() {
  local url="$1" name="$2" tries="${3:-60}"
  ui_wait "$name  $url"
  for ((i = 1; i <= tries; i++)); do curl -sf "$url" >/dev/null 2>&1 && { ui_ok "$name healthy"; return 0; }; sleep 2; done
  ui_fail "$name not healthy"; return 1
}

wait_ollama() {
  ui_wait "Ollama API  $OLLAMA_URL"
  for ((i = 1; i <= 45; i++)); do
    if curl -sf "$OLLAMA_URL/api/tags" >/dev/null 2>&1; then
      ui_ok "Ollama API reachable"
      return 0
    fi
    sleep 2
  done
  ui_fail "Ollama API not reachable"
  return 1
}

container_running() { "${COMPOSE[@]}" ps --status running 2>/dev/null | grep -qi "$1"; }

report_docker_components_up() {
  ui_section "Docker ($ACTIVE_ACCEL)"
  local any_fail=0
  container_running ollama && ui_ok "ollama [:11434] [$ACTIVE_ACCEL]" || { ui_fail "ollama down"; any_fail=1; }
  container_running backend && ui_ok "backend [:8000]" || { ui_fail "backend down"; any_fail=1; }
  container_running frontend && ui_ok "frontend [:3000]" || { ui_fail "frontend down"; any_fail=1; }
  curl -sf "$HEALTH_URL" >/dev/null 2>&1 && ui_ok "API health" || ui_warn "API not ready"
  return "$any_fail"
}

pull_models() {
  ui_section "Ollama models (required before Chroma index)"
  if ! container_running ollama; then
    ui_fail "ollama container not running — cannot pull models"
    return 1
  fi
  ui_wait "pull $OLLAMA_EMBED_MODEL (embeddings for Chroma)"
  if "${COMPOSE[@]}" exec -T ollama ollama pull "$OLLAMA_EMBED_MODEL"; then
    ui_ok "$OLLAMA_EMBED_MODEL ready"
  else
    ui_fail "failed to pull $OLLAMA_EMBED_MODEL — RAG index cannot build"
    return 1
  fi
  ui_wait "pull $OLLAMA_MODEL (chat)"
  if "${COMPOSE[@]}" exec -T ollama ollama pull "$OLLAMA_MODEL"; then
    ui_ok "$OLLAMA_MODEL ready"
  else
    ui_warn "chat model pull failed — chat may fail until fixed"
  fi
  # List models for visual confirmation
  "${COMPOSE[@]}" exec -T ollama ollama list 2>/dev/null | sed 's/^/    /' || true
}

require_compose() { [[ ${#COMPOSE_BIN[@]} -gt 0 ]] || { ui_fail "Compose missing"; exit 1; }; ui_ok "Docker Compose available"; }
has_terraform_state() { [[ -f "$ROOT/terraform/terraform.tfstate" && -s "$ROOT/terraform/terraform.tfstate" ]]; }
aws_frontend_url() { [[ -d terraform ]] && command -v terraform >/dev/null 2>&1 && (cd terraform && terraform output -raw frontend_url 2>/dev/null) || true; }
aws_health_url() { [[ -d terraform ]] && command -v terraform >/dev/null 2>&1 && (cd terraform && terraform output -raw health_url 2>/dev/null) || true; }
print_access() { ui_access_box "$FRONTEND_URL" "$BACKEND_URL/docs" "$(aws_frontend_url)" "$(aws_health_url)"; }

# Staged start avoids backend indexing before nomic-embed-text exists
compose_up_staged() {
  configure_compose || { ui_fail "Docker Compose not available"; exit 1; }

  ui_section "Stage A — Ollama only"
  if ! "${COMPOSE[@]}" up -d ollama; then
    ui_fail "failed to start ollama"
    return 1
  fi
  ui_ok "ollama container started"
  wait_ollama || return 1

  pull_models || return 1

  ui_section "Stage B — backend + frontend (embeddings ready)"
  if "${COMPOSE[@]}" up --build -d backend frontend; then
    ui_ok "backend + frontend started"
  else
    if [[ "$ACTIVE_ACCEL" == "gpu" ]]; then
      ui_warn "GPU compose failed — falling back to CPU"
      "${COMPOSE[@]}" down --remove-orphans >/dev/null 2>&1 || true
      COMPOSE=("${COMPOSE_BIN[@]}" -f docker-compose.yml); ACTIVE_ACCEL="cpu"
      printf 'cpu\n' > "$ROOT/.gpu_preference"
      "${COMPOSE[@]}" up -d ollama
      wait_ollama || return 1
      pull_models || return 1
      "${COMPOSE[@]}" up --build -d backend frontend || { ui_fail "compose up failed"; return 1; }
    else
      ui_fail "compose up backend/frontend failed"
      return 1
    fi
  fi

  # Give backend a moment; if still 503, restart once after models are warm
  sleep 5
  if ! curl -sf "$HEALTH_URL" >/dev/null 2>&1; then
    ui_warn "backend not healthy yet — restarting backend once after model warm-up"
    "${COMPOSE[@]}" restart backend >/dev/null 2>&1 || true
    sleep 4
  fi
  return 0
}

wait_rag_ready() {
  ui_section "Wait for RAG / Chroma"
  local tries=40
  for ((i = 1; i <= tries; i++)); do
    body=$(curl -sf "$HEALTH_URL" 2>/dev/null || true)
    if [[ -n "$body" ]]; then
      status=$(echo "$body" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("status",""))' 2>/dev/null || true)
      docs=$(echo "$body" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("documents_indexed",0))' 2>/dev/null || true)
      if [[ "$status" == "healthy" ]]; then
        ui_ok "RAG healthy — documents_indexed=${docs:-?}"
        # Visual Chroma confirmation via stats
        curl -sf "$BACKEND_URL/api/stats" 2>/dev/null | python3 -c '
import sys,json
try:
  d=json.load(sys.stdin)
  c=d.get("chroma") or {}
  print(f"  [CHROMA] ready={c.get("ready")} docs={d.get("documents")} collection={c.get("collection")}")
except Exception:
  pass
' || true
        return 0
      fi
    fi
    sleep 3
  done
  ui_fail "RAG still not healthy — check: docker compose logs backend | tail -50"
  ui_warn "Common fix: docker compose restart backend  (after ollama list shows nomic-embed-text)"
  return 1
}

start_local_stack() {
  ui_banner "STARTUP - Local Docker"
  ui_section "Preflight"; run_preflight local; ui_ok "preflight passed"
  require_compose; ensure_env
  compose_up_staged || exit 1
  wait_http "$HEALTH_URL" "backend" 30 || true
  wait_http "$FRONTEND_URL" "frontend" 20 || true
  wait_rag_ready || true
  report_docker_components_up || true
}

cmd_start() {
  start_local_stack
  ui_summary_box "STARTUP" "${C_OK}✔${C_RST} Docker ($ACTIVE_ACCEL)"
  print_access
  echo "Stop: bash scripts/run.sh stop"
  echo "If UI shows 503: docker compose restart backend && curl -s $HEALTH_URL"
  echo "GPU re-ask: FORCE_GPU_PROMPT=1 bash scripts/run.sh start"
}

cmd_full() {
  ui_banner "STARTUP - Full system"
  ui_section "Stage 1/4 Preflight"; run_preflight all; ui_ok "preflight passed"
  ui_section "Stage 2/4 Docker"; require_compose; ensure_env; compose_up_staged || exit 1
  wait_http "$HEALTH_URL" "backend" 30 || true
  wait_rag_ready || true
  report_docker_components_up || true
  ui_section "Stage 3/4 Terraform plan"; bash "$ROOT/scripts/aws_up.sh" plan
  ui_section "Stage 4/4 Terraform apply"
  if [[ "$FULL_YES" -eq 1 || "${RUN_FULL_YES:-}" == "1" ]]; then bash "$ROOT/scripts/aws_up.sh" apply
  else
    echo "Type yes for AWS apply:"; read -r ans || true
    [[ "${ans}" == "yes" ]] && bash "$ROOT/scripts/aws_up.sh" apply || ui_skip "AWS apply"
  fi
  print_access
}

cmd_stop() {
  ui_banner "SHUTDOWN"; configure_compose || true
  [[ ${#COMPOSE[@]} -eq 0 && ${#COMPOSE_BIN[@]} -gt 0 ]] && COMPOSE=("${COMPOSE_BIN[@]}" -f docker-compose.yml)
  if [[ ${#COMPOSE[@]} -gt 0 ]]; then
    "${COMPOSE[@]}" down --remove-orphans || true
    "${COMPOSE_BIN[@]}" -f docker-compose.yml down --remove-orphans >/dev/null 2>&1 || true
    ui_ok "Docker down"
  fi
  if has_terraform_state; then
    if [[ "$FULL_YES" -eq 1 || "${RUN_FULL_YES:-}" == "1" ]]; then bash "$ROOT/scripts/aws_up.sh" destroy
    else echo "Type yes to destroy AWS:"; read -r ans || true; [[ "${ans}" == "yes" ]] && bash "$ROOT/scripts/aws_up.sh" destroy || ui_skip "AWS left"; fi
  else ui_skip "no terraform state"; fi
  run_postflight
}

cmd_status() {
  ui_banner "STATUS"; configure_compose || true
  [[ ${#COMPOSE[@]} -gt 0 ]] && "${COMPOSE[@]}" ps || true
  [[ -f .gpu_name ]] && ui_ok "gpu=$(tr -d '\n' < .gpu_name)"
  [[ -f .gpu_preference ]] && ui_ok "preference=$(tr -d '[:space:]' < .gpu_preference)"
  curl -sf "$HEALTH_URL" 2>/dev/null | python3 -m json.tool 2>/dev/null || ui_warn "health not reachable"
  print_access
}

cmd_logs() { configure_compose || require_compose; "${COMPOSE[@]}" logs -f --tail=200; }

cmd_test() {
  ui_banner "TESTS"; run_preflight local || true
  [[ -d backend/.venv ]] || python3 -m venv backend/.venv
  # shellcheck disable=SC1091
  source backend/.venv/bin/activate
  pip install -q --upgrade pip
  pip install -q fastapi "uvicorn[standard]" "pydantic>=2.9" python-multipart "httpx>=0.27" pytest "langchain-core>=0.3"
  (cd backend && PYTHONPATH=. python -m pytest -q tests/ --tb=short)
}

cmd_aws() {
  case "${1:-plan}" in
    preflight|check) run_preflight aws ;;
    plan|apply|destroy|output) bash "$ROOT/scripts/aws_up.sh" "$1" ;;
    *) exit 1 ;;
  esac
}

ARGS=(); for a in "$@"; do case "$a" in --yes|-y) ;; *) ARGS+=("$a") ;; esac; done
set -- "${ARGS[@]+"${ARGS[@]}"}"

case "${1:-start}" in
  start|up|run) cmd_start ;;
  full|all|deploy) cmd_full ;;
  stop|down) cmd_stop ;;
  status) cmd_status ;;
  logs) cmd_logs ;;
  test) cmd_test ;;
  preflight|check) shift || true; run_preflight "${1:-local}" ;;
  postflight|audit) run_postflight ;;
  aws) shift || true; cmd_aws "${1:-plan}" ;;
  *) echo "Unknown: $1" >&2; exit 1 ;;
esac
