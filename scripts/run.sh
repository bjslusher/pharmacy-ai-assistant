#!/usr/bin/env bash
# =============================================================================
# Pharmacy AI Assistant — unified orchestrator (local Docker + AWS)
#
# Assessment / demo (one seamless path):
#   bash scripts/run.sh full          # preflight all → Docker up → AWS plan+apply
#   bash scripts/run.sh full --yes    # same, no apply confirmation
#
# Day-to-day local only:
#   bash scripts/run.sh               # preflight local + Docker only
#   bash scripts/run.sh stop|status|logs|test
#
# AWS only:
#   bash scripts/run.sh aws preflight|plan|apply|destroy
#
# Checks:
#   bash scripts/run.sh preflight all
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

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
    echo "ERROR: missing scripts/preflight.sh" >&2
    exit 1
  fi
  bash "$ROOT/scripts/preflight.sh" "$mode"
}

ensure_env() {
  if [[ ! -f backend/.env ]]; then
    if [[ -f backend/.env.example ]]; then
      cp backend/.env.example backend/.env
      echo "Created backend/.env from .env.example"
    else
      echo "LLM_PROVIDER=ollama" > backend/.env
      echo "Created minimal backend/.env"
    fi
  fi
}

wait_http() {
  local url="$1" name="$2" tries="${3:-60}"
  echo -n "Waiting for $name ($url)"
  for ((i = 1; i <= tries; i++)); do
    if curl -sf "$url" >/dev/null 2>&1; then
      echo " — ready"
      return 0
    fi
    echo -n "."
    sleep 2
  done
  echo
  echo "WARNING: $name did not become ready in time" >&2
  return 1
}

pull_models() {
  echo "=== Pulling Ollama models (if needed): $OLLAMA_MODEL, $OLLAMA_EMBED_MODEL ==="
  if "${COMPOSE[@]}" ps --status running 2>/dev/null | grep -q ollama; then
    "${COMPOSE[@]}" exec -T ollama ollama pull "$OLLAMA_MODEL" || true
    "${COMPOSE[@]}" exec -T ollama ollama pull "$OLLAMA_EMBED_MODEL" || true
  elif command -v ollama >/dev/null 2>&1; then
    ollama pull "$OLLAMA_MODEL" || true
    ollama pull "$OLLAMA_EMBED_MODEL" || true
  else
    echo "  docker compose exec ollama ollama pull $OLLAMA_MODEL"
    echo "  docker compose exec ollama ollama pull $OLLAMA_EMBED_MODEL"
  fi
}

require_compose() {
  if [[ ${#COMPOSE[@]} -eq 0 ]]; then
    echo "ERROR: Docker Compose not available (preflight should have caught this)" >&2
    exit 1
  fi
}

print_local_banner() {
  echo
  echo "=============================================="
  echo "  LOCAL STACK"
  echo "  Frontend:  $FRONTEND_URL"
  echo "  Backend:   $BACKEND_URL/docs"
  echo "  Health:    $HEALTH_URL"
  echo "=============================================="
}

print_aws_banner() {
  echo
  echo "=============================================="
  echo "  AWS (Terraform outputs)"
  if [[ -d "$ROOT/terraform" ]] && command -v terraform >/dev/null 2>&1; then
    (
      cd "$ROOT/terraform"
      terraform output 2>/dev/null || echo "  (no outputs yet — run apply)"
    )
  else
    echo "  (terraform not available)"
  fi
  echo "=============================================="
}

# Local Docker only (fast iteration)
cmd_start() {
  echo "=== STAGE 1/1 — Local Docker ==="
  run_preflight local
  echo
  require_compose
  ensure_env
  echo "=== Building and starting containers ==="
  "${COMPOSE[@]}" up --build -d
  echo "=== Waiting for services ==="
  sleep 5
  pull_models || true
  wait_http "$HEALTH_URL" "backend" 45 || true
  print_local_banner
  echo "Full system (Docker + AWS):  bash scripts/run.sh full"
  echo "Stop local:                  bash scripts/run.sh stop"
}

# Seamless assessment path: local + AWS in one command
cmd_full() {
  echo "=== Pharmacy AI — FULL SYSTEM (local Docker + AWS) ==="
  echo

  echo "=== STAGE 1/4 — Preflight (local + AWS) ==="
  run_preflight all
  echo

  echo "=== STAGE 2/4 — Local Docker stack ==="
  require_compose
  ensure_env
  "${COMPOSE[@]}" up --build -d
  sleep 5
  pull_models || true
  wait_http "$HEALTH_URL" "backend" 45 || true
  print_local_banner
  echo

  echo "=== STAGE 3/4 — AWS Terraform plan ==="
  bash "$ROOT/scripts/aws_up.sh" plan
  echo

  echo "=== STAGE 4/4 — AWS Terraform apply ==="
  if [[ "$FULL_YES" -eq 1 ]] || [[ "${RUN_FULL_YES:-}" == "1" ]]; then
    bash "$ROOT/scripts/aws_up.sh" apply
  else
    echo "About to create EC2 + S3 (Free Tier defaults). Type yes to continue:"
    read -r ans || true
    if [[ "${ans}" == "yes" ]]; then
      bash "$ROOT/scripts/aws_up.sh" apply
    else
      echo "Apply skipped. Local stack is still running."
      echo "Later: bash scripts/run.sh aws apply"
      print_local_banner
      return 0
    fi
  fi

  print_local_banner
  print_aws_banner
  echo
  echo "Local demo:  open $FRONTEND_URL"
  echo "AWS demo:    wait 10–20 min for EC2 user_data, then use terraform output frontend_url"
  echo "Teardown:    bash scripts/run.sh stop   &&   bash scripts/run.sh aws destroy"
}

cmd_stop() {
  require_compose
  echo "=== Stopping local Docker stack ==="
  "${COMPOSE[@]}" down
  echo "AWS resources (if any) are unchanged. Destroy with: bash scripts/run.sh aws destroy"
}

cmd_status() {
  echo "=== Local containers ==="
  if [[ ${#COMPOSE[@]} -gt 0 ]]; then
    "${COMPOSE[@]}" ps || true
  else
    echo "(compose unavailable)"
  fi
  echo
  echo "=== Local health ==="
  if curl -sf "$HEALTH_URL"; then echo; else echo "Backend not reachable at $HEALTH_URL"; fi
  echo
  echo "=== AWS terraform outputs (if state exists) ==="
  if [[ -d "$ROOT/terraform/.terraform" ]] || [[ -f "$ROOT/terraform/terraform.tfstate" ]]; then
    (cd "$ROOT/terraform" && terraform output 2>/dev/null) || echo "(no outputs)"
  else
    echo "(no local terraform state — run: bash scripts/run.sh full)"
  fi
}

cmd_logs() {
  require_compose
  "${COMPOSE[@]}" logs -f --tail=200
}

cmd_test() {
  echo "=== Preflight (local tools) ==="
  run_preflight local || true
  echo "=== Backend tests ==="
  if [[ -d backend/.venv ]]; then
    # shellcheck disable=SC1091
    source backend/.venv/bin/activate
  fi
  (
    cd backend
    export PYTHONPATH=.
    python3 -m pip install -q -r requirements.txt pytest python-multipart 2>/dev/null || true
    python3 -m pytest -q tests/test_expand_query.py tests/test_api_models.py tests/test_rag_helpers.py tests/test_integration_api.py
  )
}

cmd_aws() {
  local sub="${1:-plan}"
  case "$sub" in
    preflight|check)
      run_preflight aws
      ;;
    plan|apply|destroy|output)
      bash "$ROOT/scripts/aws_up.sh" "$sub"
      ;;
    *)
      echo "Usage: bash scripts/run.sh aws [preflight|plan|apply|destroy|output]" >&2
      exit 1
      ;;
  esac
}

cmd_preflight() {
  local mode="${1:-local}"
  run_preflight "$mode"
}

usage() {
  sed -n '2,20p' "$0"
}

# Strip --yes from positional handling
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
