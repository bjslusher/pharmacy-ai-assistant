#!/usr/bin/env bash
# =============================================================================
# Pharmacy AI Assistant — unified orchestrator (local Docker + AWS)
#
#   bash scripts/run.sh full [--yes]   # preflight all → Docker → AWS plan+apply
#   bash scripts/run.sh                # local Docker only
#   bash scripts/run.sh stop [--yes]   # sequential shutdown: Docker → AWS destroy
#   bash scripts/run.sh test           # venv + pytest (unit/integration/stress)
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# shellcheck disable=SC1091
source "$ROOT/scripts/status_ui.sh"

COMPOSE=(docker compose)
if ! docker compose version >/dev/null 2>&1; then
  if command -v docker-compose >/dev/null 2>&1; then
    COMPOSE=(docker-compose)
  else
    COMPOSE=()
  fi
fi

OLLAMA_MODEL="${OLLAMA_MODEL:-llama3}"
OLLAMA_EMBED_MODEL="${OLLAMA_EMBED_MODEL:-nomic-embed-text}"
FRONTEND_URL="${FRONTEND_URL:-http://localhost:3000}"
BACKEND_URL="${BACKEND_URL:-http://localhost:8000}"
HEALTH_URL="${HEALTH_URL:-http://localhost:8000/api/health}"
FULL_YES=0

for arg in "$@"; do
  case "$arg" in
    --yes|-y) FULL_YES=1 ;;
  esac
done

run_preflight() {
  local mode="${1:-local}"
  if [[ ! -f "$ROOT/scripts/preflight.sh" ]]; then
    ui_fail "scripts/preflight.sh missing"
    exit 1
  fi
  bash "$ROOT/scripts/preflight.sh" "$mode"
}

ensure_env() {
  if [[ ! -f backend/.env ]]; then
    if [[ -f backend/.env.example ]]; then
      cp backend/.env.example backend/.env
      ui_ok "backend/.env created from .env.example"
    else
      echo "LLM_PROVIDER=ollama" > backend/.env
      ui_ok "backend/.env created (minimal)"
    fi
  else
    ui_ok "backend/.env present"
  fi
}

wait_http() {
  local url="$1" name="$2" tries="${3:-60}"
  ui_wait "$name  $url"
  for ((i = 1; i <= tries; i++)); do
    if curl -sf "$url" >/dev/null 2>&1; then
      ui_ok "$name healthy"
      return 0
    fi
    sleep 2
  done
  ui_fail "$name not healthy after $((tries * 2))s"
  return 1
}

container_running() {
  local name="$1"
  "${COMPOSE[@]}" ps --status running 2>/dev/null | grep -qi "$name"
}

report_docker_components_up() {
  ui_section "Docker components"
  local any_fail=0
  if container_running ollama; then
    ui_ok "ollama          container running (:11434)"
  else
    ui_fail "ollama          not running"
    any_fail=1
  fi
  if container_running backend; then
    ui_ok "backend         container running (:8000)"
  else
    ui_fail "backend         not running"
    any_fail=1
  fi
  if container_running frontend; then
    ui_ok "frontend        container running (:3000)"
  else
    ui_fail "frontend        not running"
    any_fail=1
  fi
  if curl -sf "$HEALTH_URL" >/dev/null 2>&1; then
    ui_ok "API health      $HEALTH_URL"
  else
    ui_warn "API health      not ready yet (models may still be loading)"
  fi
  if curl -sf "$FRONTEND_URL" >/dev/null 2>&1; then
    ui_ok "UI reachable    $FRONTEND_URL"
  else
    ui_warn "UI reachable    $FRONTEND_URL not responding yet"
  fi
  return "$any_fail"
}

report_docker_components_down() {
  ui_section "Docker components (expect stopped)"
  local left
  left="$("${COMPOSE[@]}" ps -q 2>/dev/null || true)"
  if [[ -z "${left}" ]]; then
    ui_down "compose project   no running containers"
    ui_down "ollama"
    ui_down "backend"
    ui_down "frontend"
    return 0
  fi
  ui_fail "some containers still running:"
  "${COMPOSE[@]}" ps || true
  return 1
}

pull_models() {
  ui_section "Ollama models"
  if container_running ollama; then
    ui_wait "pull $OLLAMA_MODEL"
    if "${COMPOSE[@]}" exec -T ollama ollama pull "$OLLAMA_MODEL"; then
      ui_ok "model $OLLAMA_MODEL"
    else
      ui_warn "model $OLLAMA_MODEL pull failed (retry later)"
    fi
    ui_wait "pull $OLLAMA_EMBED_MODEL"
    if "${COMPOSE[@]}" exec -T ollama ollama pull "$OLLAMA_EMBED_MODEL"; then
      ui_ok "model $OLLAMA_EMBED_MODEL"
    else
      ui_warn "model $OLLAMA_EMBED_MODEL pull failed"
    fi
  else
    ui_warn "ollama not running - skip model pull"
  fi
}

require_compose() {
  if [[ ${#COMPOSE[@]} -eq 0 ]]; then
    ui_fail "Docker Compose not available"
    exit 1
  fi
  ui_ok "Docker Compose available"
}

has_terraform_state() {
  [[ -f "$ROOT/terraform/terraform.tfstate" ]] && [[ -s "$ROOT/terraform/terraform.tfstate" ]]
}

aws_frontend_url() {
  if [[ -d "$ROOT/terraform" ]] && command -v terraform >/dev/null 2>&1; then
    (cd "$ROOT/terraform" && terraform output -raw frontend_url 2>/dev/null) || true
  fi
}

aws_health_url() {
  if [[ -d "$ROOT/terraform" ]] && command -v terraform >/dev/null 2>&1; then
    (cd "$ROOT/terraform" && terraform output -raw health_url 2>/dev/null) || true
  fi
}

print_access() {
  local aws_fe aws_h
  aws_fe="$(aws_frontend_url)"
  aws_h="$(aws_health_url)"
  ui_access_box "$FRONTEND_URL" "$BACKEND_URL/docs" "${aws_fe:-}" "${aws_h:-}"
}

start_local_stack() {
  ui_banner "STARTUP - Local Docker"
  ui_section "Preflight"
  run_preflight local
  ui_ok "local preflight passed"

  require_compose
  ensure_env

  ui_section "Compose build & start"
  if "${COMPOSE[@]}" up --build -d; then
    ui_ok "docker compose up --build -d"
  else
    ui_fail "docker compose up failed"
    exit 1
  fi

  sleep 4
  pull_models || true

  ui_section "Health checks"
  wait_http "$HEALTH_URL" "backend API" 45 || true
  wait_http "$FRONTEND_URL" "frontend UI" 20 || true

  report_docker_components_up || true
}

cmd_start() {
  start_local_stack
  ui_summary_box "STARTUP" \
    "${C_OK}✔${C_RST} Docker: ollama / backend / frontend" \
    "${C_DIM}-${C_RST} AWS not started (use: bash scripts/run.sh full)"
  print_access
  echo "Stop everything:  bash scripts/run.sh stop"
}

cmd_full() {
  ui_banner "STARTUP - Full system (Docker + AWS)"

  ui_section "Stage 1/4 - Preflight (local + AWS)"
  run_preflight all
  ui_ok "preflight all passed"

  ui_section "Stage 2/4 - Local Docker"
  require_compose
  ensure_env
  if "${COMPOSE[@]}" up --build -d; then
    ui_ok "docker compose up"
  else
    ui_fail "docker compose up failed"
    exit 1
  fi
  sleep 4
  pull_models || true
  wait_http "$HEALTH_URL" "backend API" 45 || true
  report_docker_components_up || true

  ui_section "Stage 3/4 - Terraform plan"
  bash "$ROOT/scripts/aws_up.sh" plan
  ui_ok "terraform plan finished"

  ui_section "Stage 4/4 - Terraform apply (S3, IAM, ALB, ASG)"
  if [[ "$FULL_YES" -eq 1 ]] || [[ "${RUN_FULL_YES:-}" == "1" ]]; then
    bash "$ROOT/scripts/aws_up.sh" apply
  else
    echo "Creates S3, IAM, ALB, ASG. Type yes to continue:"
    read -r ans || true
    if [[ "${ans}" == "yes" ]]; then
      bash "$ROOT/scripts/aws_up.sh" apply
    else
      ui_skip "AWS apply (local Docker still up)"
      print_access
      return 0
    fi
  fi

  ui_summary_box "STARTUP" \
    "${C_OK}✔${C_RST} Docker local stack" \
    "${C_OK}✔${C_RST} Terraform apply (S3 / IAM / ALB / ASG)" \
    "${C_WARN}…${C_RST} ASG instances need 15-25+ min before AWS UI is ready"
  print_access
  echo "Stop:  bash scripts/run.sh stop --yes"
}

cmd_stop() {
  ui_banner "SHUTDOWN - sequential teardown"

  ui_section "[1/2] Docker Compose"
  if [[ ${#COMPOSE[@]} -gt 0 ]]; then
    if "${COMPOSE[@]}" down --remove-orphans; then
      ui_ok "docker compose down"
    else
      ui_warn "compose down returned non-zero (continuing)"
    fi
    report_docker_components_down || true
  else
    ui_skip "Docker Compose not available"
  fi

  ui_section "[2/2] AWS / Terraform destroy"
  if ! has_terraform_state; then
    ui_skip "no terraform.tfstate - nothing to destroy from this machine"
    ui_summary_box "SHUTDOWN" \
      "${C_OK}✔${C_RST} Docker stopped" \
      "${C_DIM}-${C_RST} AWS destroy skipped (no state)"
    return 0
  fi

  if [[ "$FULL_YES" -eq 1 ]] || [[ "${RUN_FULL_YES:-}" == "1" ]]; then
    bash "$ROOT/scripts/aws_up.sh" destroy
  else
    echo "Permanently deletes ALB, ASG, EC2, S3, IAM. Type yes:"
    read -r ans || true
    if [[ "${ans}" == "yes" ]]; then
      bash "$ROOT/scripts/aws_up.sh" destroy
    else
      ui_skip "AWS destroy (Docker already down)"
      ui_summary_box "SHUTDOWN" \
        "${C_OK}✔${C_RST} Docker stopped" \
        "${C_WARN}⚠${C_RST} AWS left running - bash scripts/run.sh aws destroy"
      return 0
    fi
  fi

  ui_summary_box "SHUTDOWN" \
    "${C_OK}✔${C_RST} Docker: ollama / backend / frontend down" \
    "${C_OK}✔${C_RST} Terraform destroy completed (ALB, ASG, S3, IAM)" \
    "${C_OK}✔${C_RST} ASG removed - will not launch replacement instances"
}

cmd_status() {
  ui_banner "STATUS"
  ui_section "Docker"
  if [[ ${#COMPOSE[@]} -gt 0 ]]; then
    "${COMPOSE[@]}" ps || true
    report_docker_components_up || true
  else
    ui_warn "compose unavailable"
  fi
  ui_section "AWS / Terraform"
  if has_terraform_state; then
    (cd "$ROOT/terraform" && terraform output 2>/dev/null) || ui_warn "no outputs"
  else
    ui_skip "no terraform state"
  fi
  print_access
}

cmd_logs() {
  require_compose
  "${COMPOSE[@]}" logs -f --tail=200
}

# Create backend/.venv, install test deps, run full pytest suite
cmd_test() {
  ui_banner "BACKEND TESTS"
  run_preflight local || true

  ui_section "Python venv"
  if [[ ! -d "$ROOT/backend/.venv" ]]; then
    ui_wait "python3 -m venv backend/.venv"
    python3 -m venv "$ROOT/backend/.venv"
    ui_ok "venv created: backend/.venv"
  else
    ui_ok "venv exists: backend/.venv"
  fi

  # shellcheck disable=SC1091
  source "$ROOT/backend/.venv/bin/activate"
  PY="$ROOT/backend/.venv/bin/python"
  PIP="$ROOT/backend/.venv/bin/pip"

  ui_section "Install test dependencies"
  "$PIP" install -q --upgrade pip
  # Lightweight set enough for unit/integration/stress (mocked RAG)
  "$PIP" install -q \
    "fastapi==0.115.0" \
    "uvicorn[standard]==0.30.6" \
    "pydantic>=2.9.2,<3" \
    "python-multipart==0.0.9" \
    "httpx>=0.27.2,<0.29" \
    "pytest>=8.3.3" \
    "langchain-core>=0.3.6,<0.4"
  ui_ok "pytest + fastapi + langchain-core installed in venv"

  ui_section "Run pytest"
  (
    cd "$ROOT/backend"
    export PYTHONPATH=.
    "$PY" -m pytest -q tests/ \
      --tb=short
  )
  ui_ok "all tests finished"
}

cmd_aws() {
  local sub="${1:-plan}"
  case "$sub" in
    preflight|check) run_preflight aws ;;
    plan|apply|destroy|output) bash "$ROOT/scripts/aws_up.sh" "$sub" ;;
    *)
      echo "Usage: bash scripts/run.sh aws [preflight|plan|apply|destroy|output]" >&2
      exit 1
      ;;
  esac
}

cmd_preflight() {
  run_preflight "${1:-local}"
}

usage() {
  sed -n '2,11p' "$0"
}

ARGS=()
for a in "$@"; do
  case "$a" in
    --yes|-y) ;;
    *) ARGS+=("$a") ;;
  esac
done
set -- "${ARGS[@]+"${ARGS[@]}"}"

case "${1:-start}" in
  start|up|run)       cmd_start ;;
  full|all|deploy)    cmd_full ;;
  stop|down)          cmd_stop ;;
  status)             cmd_status ;;
  logs)               cmd_logs ;;
  test)               cmd_test ;;
  preflight|check)    shift || true; cmd_preflight "${1:-local}" ;;
  aws)                shift || true; cmd_aws "${1:-plan}" ;;
  help|-h|--help)     usage ;;
  *)
    echo "Unknown command: $1" >&2
    usage
    exit 1
    ;;
esac
