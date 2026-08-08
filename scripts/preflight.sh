#!/usr/bin/env bash
# =============================================================================
# Pharmacy AI Assistant — unified preflight (FAIL FAST)
#
# Modes: local | aws | all
# Also writes .gpu_status for run.sh (gpu|cpu) after local checks.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MODE="${1:-local}"
ERRORS=0
GPU_MODE="cpu"

ok()   { echo "  [OK]  $*"; }
fail() { echo "  [FAIL] $*" >&2; ERRORS=$((ERRORS + 1)); }
warn() { echo "  [WARN] $*" >&2; }
info() { echo "  $*"; }

die_if_errors() {
  if [[ "$ERRORS" -gt 0 ]]; then
    echo >&2
    echo "=== PREFLIGHT FAILED ($ERRORS issue(s)) — fix above before starting ===" >&2
    echo "    bash scripts/preflight.sh $MODE" >&2
    exit 1
  fi
  echo "=== PREFLIGHT PASSED ($MODE) ==="
  if [[ "$MODE" == "local" || "$MODE" == "docker" || "$MODE" == "stack" || "$MODE" == "all" || "$MODE" == "full" ]]; then
    echo "=== GPU MODE: $GPU_MODE ==="
  fi
}

# Detect host NVIDIA + Docker GPU runtime. Sets GPU_MODE=gpu|cpu and .gpu_status
check_gpu() {
  echo "--- GPU / acceleration ---"
  local host_gpu=0 docker_gpu=0

  if command -v nvidia-smi >/dev/null 2>&1; then
    if nvidia-smi >/dev/null 2>&1; then
      host_gpu=1
      ok "nvidia-smi: $(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null | head -1)"
    else
      warn "nvidia-smi present but failed — driver issue?"
    fi
  else
    warn "nvidia-smi not found on host — Ollama will run on CPU (slower)"
  fi

  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    if docker info 2>/dev/null | grep -qi 'Runtimes:.*nvidia'; then
      docker_gpu=1
      ok "Docker NVIDIA runtime registered"
    elif docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi >/dev/null 2>&1; then
      docker_gpu=1
      ok "Docker --gpus all works"
    else
      # cheaper probe without pulling cuda image if possible
      if docker info 2>/dev/null | grep -qi nvidia; then
        docker_gpu=1
        ok "Docker reports NVIDIA capability"
      else
        warn "Docker cannot use GPU (enable GPU in Docker Desktop / install nvidia-container-toolkit)"
      fi
    fi
  fi

  if [[ "$host_gpu" -eq 1 && "$docker_gpu" -eq 1 ]]; then
    GPU_MODE="gpu"
    ok "GPU path enabled — Ollama will use NVIDIA (compose gpus: all)"
  elif [[ "$host_gpu" -eq 1 && "$docker_gpu" -eq 0 ]]; then
    GPU_MODE="cpu"
    warn "GPU on host but not available to Docker — falling back to CPU Ollama"
    info "Fix: Docker Desktop → Settings → Resources → enable GPU; WSL2 + nvidia-container-toolkit"
  else
    GPU_MODE="cpu"
    warn "No usable GPU for containers — CPU fallback (still works, slower generation)"
  fi

  printf '%s\n' "$GPU_MODE" > "$ROOT/.gpu_status"
  ok "wrote .gpu_status=$GPU_MODE"
}

preflight_local() {
  echo "=== Preflight: local Docker stack ==="

  if command -v docker >/dev/null 2>&1; then
    ok "docker: $(docker --version 2>&1 | head -1)"
  else
    fail "docker not found — install Docker Desktop (WSL2 backend) or Docker Engine"
  fi

  if docker compose version >/dev/null 2>&1; then
    ok "docker compose: $(docker compose version 2>&1 | head -1)"
  elif command -v docker-compose >/dev/null 2>&1; then
    ok "docker-compose (legacy): $(docker-compose version 2>&1 | head -1)"
  else
    fail "Docker Compose not found"
  fi

  if command -v curl >/dev/null 2>&1; then
    ok "curl available (health checks)"
  else
    fail "curl not found — sudo apt install curl"
  fi

  if command -v git >/dev/null 2>&1; then
    ok "git available"
  else
    warn "git not found (only needed for clone/pull)"
  fi

  if command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1; then
      ok "Docker daemon reachable"
    else
      fail "Docker daemon not reachable — start Docker Desktop / sudo service docker start"
      info "WSL: ensure Docker Desktop → Settings → Resources → WSL integration is on"
    fi
  fi

  check_gpu

  [[ -f "$ROOT/docker-compose.yml" ]] && ok "docker-compose.yml" || fail "missing docker-compose.yml"
  [[ -f "$ROOT/docker-compose.cpu.yml" ]] && ok "docker-compose.cpu.yml (CPU fallback)" || warn "missing docker-compose.cpu.yml"
  [[ -f "$ROOT/backend/Dockerfile" ]] && ok "backend/Dockerfile" || fail "missing backend/Dockerfile"
  [[ -f "$ROOT/frontend/Dockerfile" ]] && ok "frontend/Dockerfile" || fail "missing frontend/Dockerfile"
  [[ -f "$ROOT/backend/main.py" ]] && ok "backend/main.py" || fail "missing backend/main.py"
  [[ -f "$ROOT/backend/rag_service.py" ]] && ok "backend/rag_service.py" || fail "missing backend/rag_service.py"

  local seed=0
  if [[ -d "$ROOT/backend/source_data" ]]; then
    seed=$(find "$ROOT/backend/source_data" -type f -name '*.txt' 2>/dev/null | wc -l | tr -d ' ')
  fi
  if [[ "${seed:-0}" -ge 1 ]]; then
    ok "seed knowledge files: $seed (backend/source_data) — these become Chroma embeddings"
    for f in common_controlled_imprints.txt dea_schedules_overview.txt pharmacist_responsibilities.txt; do
      if [[ -f "$ROOT/backend/source_data/$f" ]]; then
        ok "  seed: $f"
      else
        warn "  missing optional seed name: $f"
      fi
    done
  else
    fail "no .txt seed files under backend/source_data — RAG will have nothing to index"
  fi

  if [[ -f "$ROOT/backend/.env" ]]; then
    ok "backend/.env present"
  elif [[ -f "$ROOT/backend/.env.example" ]]; then
    warn "backend/.env missing — will be created from .env.example on start"
  else
    warn "no backend/.env or .env.example — start will create a minimal env"
  fi

  if command -v df >/dev/null 2>&1; then
    local avail_kb
    avail_kb=$(df -Pk "$ROOT" 2>/dev/null | awk 'NR==2{print $4}')
    if [[ -n "${avail_kb:-}" ]]; then
      local avail_gb=$((avail_kb / 1024 / 1024))
      if [[ "$avail_gb" -lt 5 ]]; then
        fail "low disk space: ~${avail_gb}GB free (need several GB for images/models)"
      elif [[ "$avail_gb" -lt 10 ]]; then
        warn "disk space only ~${avail_gb}GB free — model pulls may fail"
      else
        ok "disk space: ~${avail_gb}GB free on volume"
      fi
    fi
  fi

  check_port() {
    local port="$1" name="$2"
    if command -v ss >/dev/null 2>&1; then
      if ss -ltn 2>/dev/null | grep -q ":${port} "; then
        warn "port $port in use ($name) — if not this stack, stop the other process"
      else
        ok "port $port free ($name)"
      fi
    elif command -v netstat >/dev/null 2>&1; then
      if netstat -ltn 2>/dev/null | grep -q ":${port} "; then
        warn "port $port in use ($name)"
      else
        ok "port $port free ($name)"
      fi
    else
      info "skip port check for $port (ss/netstat not available)"
    fi
  }
  check_port 3000 "frontend"
  check_port 8000 "backend API"
  check_port 11434 "ollama"

  if command -v python3 >/dev/null 2>&1; then
    ok "python3: $(python3 --version 2>&1)"
  else
    warn "python3 not found — local pytest via run.sh test will fail"
  fi
}

preflight_aws() {
  echo "=== Preflight: AWS ==="
  if [[ ! -f "$ROOT/scripts/aws_preflight.sh" ]]; then
    fail "missing scripts/aws_preflight.sh"
    return
  fi
  if bash "$ROOT/scripts/aws_preflight.sh"; then
    ok "aws_preflight.sh passed"
  else
    fail "aws_preflight.sh failed — see [FAIL] lines above"
  fi
}

case "$MODE" in
  local|docker|stack)
    preflight_local
    die_if_errors
    ;;
  aws|cloud)
    preflight_aws
    die_if_errors
    ;;
  all|full)
    preflight_local
    echo
    local_errors=$ERRORS
    if ! bash "$ROOT/scripts/aws_preflight.sh"; then
      ERRORS=$((local_errors + 1))
    else
      ERRORS=$local_errors
      ok "aws_preflight.sh passed"
    fi
    die_if_errors
    ;;
  -h|--help|help)
    sed -n '2,16p' "$0"
    exit 0
    ;;
  *)
    echo "Usage: $0 [local|aws|all]" >&2
    exit 1
    ;;
esac
