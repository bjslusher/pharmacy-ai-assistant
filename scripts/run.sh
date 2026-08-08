#!/usr/bin/env bash
# =============================================================================
# Pharmacy AI Assistant — one-command orchestrator
# Usage:
#   bash scripts/run.sh                # local Docker stack
#   bash scripts/run.sh stop|status|logs|test
#   bash scripts/run.sh aws            # AWS preflight + terraform plan
#   bash scripts/run.sh aws preflight  # AWS checks only (seconds)
#   bash scripts/run.sh aws apply      # preflight + apply
#   bash scripts/run.sh aws destroy
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

COMPOSE=(docker compose)
if ! docker compose version >/dev/null 2>&1; then
  if command -v docker-compose >/dev/null 2>&1; then
    COMPOSE=(docker-compose)
  else
    # Only required for local docker commands — AWS path has its own checks
    COMPOSE=()
  fi
fi

OLLAMA_MODEL="${OLLAMA_MODEL:-llama3}"
OLLAMA_EMBED_MODEL="${OLLAMA_EMBED_MODEL:-nomic-embed-text}"
FRONTEND_URL="${FRONTEND_URL:-http://localhost:3000}"
BACKEND_URL="${BACKEND_URL:-http://localhost:8000}"
HEALTH_URL="${HEALTH_URL:-http://localhost:8000/api/health}"

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

require_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: docker not found" >&2
    exit 1
  fi
  if [[ ${#COMPOSE[@]} -eq 0 ]]; then
    echo "ERROR: Docker Compose not found" >&2
    exit 1
  fi
}

cmd_start() {
  echo "=== Pharmacy AI Assistant — starting local Docker stack ==="
  require_docker
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
  echo "AWS path (separate): bash scripts/run.sh aws preflight"
}

cmd_stop() {
  require_docker
  echo "=== Stopping stack ==="
  "${COMPOSE[@]}" down
}

cmd_status() {
  require_docker
  echo "=== Containers ==="
  "${COMPOSE[@]}" ps || true
  echo
  echo "=== Health ==="
  if curl -sf "$HEALTH_URL"; then echo; else echo "Backend not reachable at $HEALTH_URL"; fi
}

cmd_logs() {
  require_docker
  "${COMPOSE[@]}" logs -f --tail=200
}

cmd_test() {
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
  # Always go through aws_up.sh which sources preflight first
  bash "$ROOT/scripts/aws_up.sh" "$sub"
}

usage() {
  sed -n '2,14p' "$0"
}

case "${1:-start}" in
  start|up|run) cmd_start ;;
  stop|down)    cmd_stop ;;
  status)       cmd_status ;;
  logs)         cmd_logs ;;
  test)         cmd_test ;;
  aws)          shift || true; cmd_aws "${1:-plan}" ;;
  help|-h|--help) usage ;;
  *)
    echo "Unknown command: $1" >&2
    usage
    exit 1
    ;;
esac
