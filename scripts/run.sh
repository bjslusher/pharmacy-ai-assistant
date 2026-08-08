#!/usr/bin/env bash
# Pharmacy AI Assistant orchestrator
# --yes exports FULL_YES so GPU selection uses the detected device
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
FULL_YES=0
ACTIVE_ACCEL="cpu"

for arg in "$@"; do case "$arg" in --yes|-y) FULL_YES=1 ;; esac; done
export FULL_YES

run_preflight() {
  local mode="${1:-local}"
  [[ -f "$ROOT/scripts/preflight.sh" ]] || { ui_fail "scripts/preflight.sh missing"; exit 1; }
  FULL_YES="$FULL_YES" RUN_FULL_YES="${RUN_FULL_YES:-$FULL_YES}" bash "$ROOT/scripts/preflight.sh" "$mode"
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

compose_up_with_fallback() {
  configure_compose || { ui_fail "Docker Compose not available"; exit 1; }
  ui_section "Compose build & start ($ACTIVE_ACCEL)"
  if "${COMPOSE[@]}" up --build -d; then ui_ok "docker compose up ($ACTIVE_ACCEL)"; return 0; fi
  if [[ "$ACTIVE_ACCEL" == "gpu" ]]; then
    ui_warn "GPU compose failed — falling back to CPU"
    "${COMPOSE[@]}" down --remove-orphans >/dev/null 2>&1 || true
    COMPOSE=("${COMPOSE_BIN[@]}" -f docker-compose.yml); ACTIVE_ACCEL="cpu"
    printf 'cpu\n' > "$ROOT/.gpu_preference"
    if "${COMPOSE[@]}" up --build -d; then ui_ok "docker compose up (CPU fallback)"; return 0; fi
  fi
  ui_fail "docker compose up failed"; return 1
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
  ui_section "Ollama models"
  if container_running ollama; then
    "${COMPOSE[@]}" exec -T ollama ollama pull "$OLLAMA_MODEL" && ui_ok "$OLLAMA_MODEL" || ui_warn "pull failed"
    "${COMPOSE[@]}" exec -T ollama ollama pull "$OLLAMA_EMBED_MODEL" && ui_ok "$OLLAMA_EMBED_MODEL" || ui_warn "embed pull failed"
  fi
}

require_compose() { [[ ${#COMPOSE_BIN[@]} -gt 0 ]] || { ui_fail "Compose missing"; exit 1; }; ui_ok "Docker Compose available"; }
has_terraform_state() { [[ -f "$ROOT/terraform/terraform.tfstate" && -s "$ROOT/terraform/terraform.tfstate" ]]; }
aws_frontend_url() { [[ -d terraform ]] && command -v terraform >/dev/null 2>&1 && (cd terraform && terraform output -raw frontend_url 2>/dev/null) || true; }
aws_health_url() { [[ -d terraform ]] && command -v terraform >/dev/null 2>&1 && (cd terraform && terraform output -raw health_url 2>/dev/null) || true; }
print_access() { ui_access_box "$FRONTEND_URL" "$BACKEND_URL/docs" "$(aws_frontend_url)" "$(aws_health_url)"; }

start_local_stack() {
  ui_banner "STARTUP - Local Docker"
  ui_section "Preflight"; run_preflight local; ui_ok "preflight passed"
  require_compose; ensure_env
  compose_up_with_fallback || exit 1
  sleep 4; pull_models || true
  wait_http "$HEALTH_URL" "backend" 45 || true
  wait_http "$FRONTEND_URL" "frontend" 20 || true
  report_docker_components_up || true
}

cmd_start() {
  start_local_stack
  ui_summary_box "STARTUP" "${C_OK}✔${C_RST} Docker ($ACTIVE_ACCEL)"
  print_access
  echo "Stop: bash scripts/run.sh stop"
  echo "GPU re-ask: FORCE_GPU_PROMPT=1 bash scripts/run.sh start"
}

cmd_full() {
  ui_banner "STARTUP - Full system"
  ui_section "Stage 1/4 Preflight"; run_preflight all; ui_ok "preflight passed"
  ui_section "Stage 2/4 Docker"; require_compose; ensure_env; compose_up_with_fallback || exit 1
  sleep 4; pull_models || true; wait_http "$HEALTH_URL" "backend" 45 || true; report_docker_components_up || true
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
}

cmd_status() {
  ui_banner "STATUS"; configure_compose || true
  [[ ${#COMPOSE[@]} -gt 0 ]] && "${COMPOSE[@]}" ps || true
  [[ -f .gpu_name ]] && ui_ok "gpu=$(tr -d '\n' < .gpu_name)"
  [[ -f .gpu_preference ]] && ui_ok "preference=$(tr -d '[:space:]' < .gpu_preference)"
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
  aws) shift || true; cmd_aws "${1:-plan}" ;;
  *) echo "Unknown: $1" >&2; exit 1 ;;
esac
