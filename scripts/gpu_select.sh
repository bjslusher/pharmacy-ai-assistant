#!/usr/bin/env bash
# =============================================================================
# GPU capability detect + interactive preference (gpu | cpu)
#
# Writes:
#   .gpu_status       — hardware capability: gpu | cpu
#   .gpu_preference   — user choice: gpu | cpu
#
# Env overrides (non-interactive):
#   GPU_PREFERENCE=gpu|cpu
#   GPU_MODE=gpu|cpu          (alias for preference)
#   FORCE_GPU_PROMPT=1        re-ask even if preference file exists
# =============================================================================
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
STATUS_FILE="$ROOT/.gpu_status"
PREF_FILE="$ROOT/.gpu_preference"

ok()   { echo "  [OK]  $*"; }
warn() { echo "  [WARN] $*" >&2; }
info() { echo "  $*"; }

detect_gpu_capability() {
  local host_gpu=0 docker_gpu=0

  if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
    host_gpu=1
    ok "nvidia-smi: $(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null | head -1 | tr -s ' ')"
  else
    warn "No working nvidia-smi on host"
  fi

  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    if docker info 2>/dev/null | grep -qiE 'Runtimes:.*nvidia|nvidia'; then
      docker_gpu=1
      ok "Docker NVIDIA runtime / capability reported"
    else
      warn "Docker does not report NVIDIA runtime"
    fi
  fi

  if [[ "$host_gpu" -eq 1 && "$docker_gpu" -eq 1 ]]; then
    echo gpu
  elif [[ "$host_gpu" -eq 1 ]]; then
    warn "GPU on host but Docker may not pass it through — preference still allowed; runtime will fall back if needed"
    echo gpu
  else
    echo cpu
  fi
}

# Resolve preference: env > existing file > prompt (if capable) > cpu
resolve_gpu_preference() {
  local capability="$1"
  local pref=""

  # Explicit env wins
  if [[ -n "${GPU_PREFERENCE:-}" ]]; then
    pref="$(echo "$GPU_PREFERENCE" | tr '[:upper:]' '[:lower:]')"
  elif [[ -n "${GPU_MODE:-}" ]]; then
    pref="$(echo "$GPU_MODE" | tr '[:upper:]' '[:lower:]')"
  fi

  if [[ "$pref" == "gpu" || "$pref" == "cpu" ]]; then
    ok "GPU preference from environment: $pref"
    echo "$pref"
    return 0
  fi

  # Reuse saved preference unless forced
  if [[ "${FORCE_GPU_PROMPT:-0}" != "1" && -f "$PREF_FILE" ]]; then
    pref="$(tr -d '[:space:]' < "$PREF_FILE" | tr '[:upper:]' '[:lower:]')"
    if [[ "$pref" == "gpu" || "$pref" == "cpu" ]]; then
      ok "GPU preference from .gpu_preference: $pref (set FORCE_GPU_PROMPT=1 to re-ask)"
      echo "$pref"
      return 0
    fi
  fi

  # No GPU capability → force cpu
  if [[ "$capability" != "gpu" ]]; then
    warn "No usable GPU — locking preference to cpu"
    echo cpu
    return 0
  fi

  # Interactive prompt when TTY available
  if [[ -t 0 ]]; then
    echo
    echo "  NVIDIA GPU detected."
    echo "  Use GPU for Ollama? (faster)  [Y] GPU  /  [n] CPU only"
    echo "  GPU path will automatically fall back to CPU if container start fails."
    printf "  Choice [Y/n]: "
    read -r ans || true
    case "${ans:-Y}" in
      n|N|no|NO|cpu|CPU) pref=cpu ;;
      *) pref=gpu ;;
    esac
    ok "Selected: $pref"
  else
    # Non-interactive default: prefer GPU when capable
    pref=gpu
    ok "No TTY — defaulting preference to gpu (override with GPU_PREFERENCE=cpu)"
  fi

  echo "$pref"
}

# Main: detect, choose, persist
capability="$(detect_gpu_capability)"
printf '%s\n' "$capability" > "$STATUS_FILE"
ok "wrote .gpu_status=$capability"

preference="$(resolve_gpu_preference "$capability")"
printf '%s\n' "$preference" > "$PREF_FILE"
ok "wrote .gpu_preference=$preference"

echo "=== GPU CAPABILITY: $capability | PREFERENCE: $preference ==="
