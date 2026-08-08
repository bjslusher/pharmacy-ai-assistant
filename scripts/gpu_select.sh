#!/usr/bin/env bash
# =============================================================================
# GPU capability detect + interactive preference (gpu | cpu)
#
# Writes:
#   .gpu_status       — hardware capability: gpu | cpu
#   .gpu_preference   — user choice: gpu | cpu
#   .gpu_name         — human-readable device name from nvidia-smi
#
# Env: GPU_PREFERENCE=gpu|cpu  GPU_MODE=gpu|cpu  FORCE_GPU_PROMPT=1
# =============================================================================
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
STATUS_FILE="$ROOT/.gpu_status"
PREF_FILE="$ROOT/.gpu_preference"
NAME_FILE="$ROOT/.gpu_name"

ok()   { echo "  [OK]  $*"; }
warn() { echo "  [WARN] $*" >&2; }
info() { echo "  $*"; }

# Returns capability via stdout (gpu|cpu). Sets GPU_NAME / GPU_MEM globals.
GPU_NAME="(none)"
GPU_MEM=""
GPU_DRIVER=""

detect_gpu_capability() {
  local host_gpu=0 docker_gpu=0
  GPU_NAME="(none)"
  GPU_MEM=""
  GPU_DRIVER=""

  if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
    host_gpu=1
    GPU_NAME="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    GPU_MEM="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader 2>/dev/null | head -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    GPU_DRIVER="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -z "$GPU_NAME" ]] && GPU_NAME="NVIDIA GPU (name unavailable)"
    ok "Host GPU identified: ${GPU_NAME}"
    [[ -n "$GPU_MEM" ]] && ok "  VRAM: ${GPU_MEM}"
    [[ -n "$GPU_DRIVER" ]] && ok "  Driver: ${GPU_DRIVER}"
  else
    warn "No working nvidia-smi on host — no named GPU available"
  fi

  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    if docker info 2>/dev/null | grep -qiE 'Runtimes:.*nvidia|nvidia'; then
      docker_gpu=1
      ok "Docker NVIDIA runtime / capability reported"
    else
      warn "Docker does not report NVIDIA runtime"
    fi
  fi

  # Persist name for other scripts / status
  printf '%s\n' "$GPU_NAME" > "$NAME_FILE"

  if [[ "$host_gpu" -eq 1 && "$docker_gpu" -eq 1 ]]; then
    echo gpu
  elif [[ "$host_gpu" -eq 1 ]]; then
    warn "${GPU_NAME} is on the host but Docker may not pass it through — runtime will fall back to CPU if GPU compose fails"
    echo gpu
  else
    echo cpu
  fi
}

resolve_gpu_preference() {
  local capability="$1"
  local pref=""

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

  if [[ "${FORCE_GPU_PROMPT:-0}" != "1" && -f "$PREF_FILE" ]]; then
    pref="$(tr -d '[:space:]' < "$PREF_FILE" | tr '[:upper:]' '[:lower:]')"
    if [[ "$pref" == "gpu" || "$pref" == "cpu" ]]; then
      ok "GPU preference from .gpu_preference: $pref (FORCE_GPU_PROMPT=1 to re-ask)"
      echo "$pref"
      return 0
    fi
  fi

  if [[ "$capability" != "gpu" ]]; then
    warn "No usable GPU — locking preference to cpu"
    echo cpu
    return 0
  fi

  if [[ -t 0 ]]; then
    echo
    echo "  ┌─────────────────────────────────────────────────────────┐"
    echo "  │  Detected GPU: ${GPU_NAME}"
    [[ -n "$GPU_MEM" ]] && echo "  │  VRAM:          ${GPU_MEM}"
    [[ -n "$GPU_DRIVER" ]] && echo "  │  Driver:        ${GPU_DRIVER}"
    echo "  └─────────────────────────────────────────────────────────┘"
    echo
    echo "  Use this GPU for Ollama? (faster generation)"
    echo "    [Y] GPU  — primary path; CPU used automatically if GPU start fails"
    echo "    [n] CPU  — skip GPU for this run"
    printf "  Choice [Y/n]: "
    read -r ans || true
    case "${ans:-Y}" in
      n|N|no|NO|cpu|CPU) pref=cpu ;;
      *) pref=gpu ;;
    esac
    ok "Selected: $pref  (device: ${GPU_NAME})"
  else
    pref=gpu
    ok "No TTY — defaulting to gpu for ${GPU_NAME} (override: GPU_PREFERENCE=cpu)"
  fi

  echo "$pref"
}

capability="$(detect_gpu_capability)"
printf '%s\n' "$capability" > "$STATUS_FILE"
ok "wrote .gpu_status=$capability"

preference="$(resolve_gpu_preference "$capability")"
printf '%s\n' "$preference" > "$PREF_FILE"
ok "wrote .gpu_preference=$preference"

echo "=== GPU: ${GPU_NAME} | CAPABILITY: $capability | PREFERENCE: $preference ==="
