#!/usr/bin/env bash
# =============================================================================
# Pharmacy AI Assistant — one-command orchestrator
#
# Every long path runs preflight FIRST (fail-fast):
#   local Docker  → scripts/preflight.sh local
#   AWS           → scripts/preflight.sh aws  (→ aws_preflight.sh)
#
# Usage:
#   bash scripts/run.sh                 # preflight local + start Docker stack
#   bash scripts/run.sh preflight       # local checks only
#   bash scripts/run.sh preflight all   # local + AWS
#   bash scripts/run.sh stop|status|logs|test
#   bash scripts/run.sh aws             # AWS preflight + terraform plan
#   bash scripts/run.sh aws preflight|plan|apply|destroy
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

cmd_start() {
  echo "=== Pharmacy AI Assistant — orchestrated start ==="
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
  echo
  echo "=============================================="
  echo "  Frontend:  $FRONTEND_URL"
  echo "  Backend:   $BACKEND_URL/docs"
  echo "  Health:    $HEALTH_URL"
  echo "=============================================="
  echo "AWS:  bash scripts/run.sh aws preflight"
  echo "Stop: bash scripts/run.sh stop"
}

cmd_stop() {
  require_compose
  echo "=== Stopping stack ==="
  "${COMPOSE[@]}" down
}

cmd_status() {
  require_compose
  echo "=== Containers ==="
  "${COMPOSE[@]}" ps || true
  echo
  echo "=== Health ==="
  if curl -sf "$HEALTH_URL"; then echo; else echo "Backend not reachable at $HEALTH_URL"; fi
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
      # aws_up.sh runs aws_preflight again internally before terraform
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
  sed -n '2,18p' "$0"
}

case "${1:-start}" in
  start|up|run)     cmd_start ;;
  stop|down)        cmd_stop ;;
  status)           cmd_status ;;
  logs)             cmd_logs ;;
  test)             cmd_test ;;
  preflight|check)  shift || true; cmd_preflight "${1:-local}" ;;
  aws)              shift || true; cmd_aws "${1:-plan}" ;;
  help|-h|--help)   usage ;;
  *)
    echo "Unknown command: $1" >&2
    usage
    exit 1
    ;;
esac
