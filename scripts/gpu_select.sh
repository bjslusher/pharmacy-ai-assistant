#!/usr/bin/env bash
# =============================================================================
# GPU capability detect + interactive preference (gpu | cpu)
#
# Writes:
#   .gpu_status       — hardware capability: gpu | cpu
#   .gpu_preference   — user choice: gpu | cpu
#   .gpu_name         — human-readable device name from nvidia-smi
#
# IMPORTANT: status messages go to stderr. Only pure gpu|cpu is written to stdout
# from the detect/resolve helpers so command substitution stays clean.
#
# Env:
#   GPU_PREFERENCE=gpu|cpu
#   GPU_MODE=gpu|cpu
#   FORCE_GPU_PROMPT=1        re-ask even if preference file exists
#   FULL_YES=1 / RUN_FULL_YES=1  treat as affirmative GPU when capable (no TTY)
# =============================================================================
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
STATUS_FILE="$ROOT/.gpu_status"
PREF_FILE="$ROOT/.gpu_preference"
NAME_FILE="$ROOT/.gpu_name"

# All human-readable logs → stderr (never pollute $(...) captures)
ok()   { echo "  [OK]  $*" >&2; }
warn() { echo "  [WARN] $*" >&2; }
info() { echo "  $*" >&2; }

GPU_NAME="(none)"
GPU_MEM=""
GPU_DRIVER=""

# Prints ONLY "gpu" or "cpu" on stdout.
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

  printf '%s\n' "$GPU_NAME" > "$NAME_FILE"

  if [[ "$host_gpu" -eq 1 && "$docker_gpu" -eq 1 ]]; then
    printf 'gpu\n'
  elif [[ "$host_gpu" -eq 1 ]]; then
    warn "${GPU_NAME} is on the host but Docker may not pass it through — runtime will fall back to CPU if GPU compose fails"
    printf 'gpu\n'
  else
    printf 'cpu\n'
  fi
}

# Prints ONLY "gpu" or "cpu" on stdout.
resolve_gpu_preference() {
  local capability="$1"
  # Strip accidental whitespace/newlines from capture
  capability="$(echo "$capability" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
  local pref=""

  # Explicit env wins
  if [[ -n "${GPU_PREFERENCE:-}" ]]; then
    pref="$(echo "$GPU_PREFERENCE" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  elif [[ -n "${GPU_MODE:-}" ]]; then
    pref="$(echo "$GPU_MODE" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  fi

  if [[ "$pref" == "gpu" || "$pref" == "cpu" ]]; then
    ok "GPU preference from environment: $pref"
    printf '%s\n' "$pref"
    return 0
  fi

  # Reuse saved preference unless forced
  if [[ "${FORCE_GPU_PROMPT:-0}" != "1" && -f "$PREF_FILE" ]]; then
    pref="$(tr -d '[:space:]' < "$PREF_FILE" | tr '[:upper:]' '[:lower:]')"
    if [[ "$pref" == "gpu" || "$pref" == "cpu" ]]; then
      ok "GPU preference from .gpu_preference: $pref (set FORCE_GPU_PROMPT=1 to re-ask)"
      printf '%s\n' "$pref"
      return 0
    fi
  fi

  # No GPU capability → force cpu
  if [[ "$capability" != "gpu" ]]; then
    warn "No usable GPU — locking preference to cpu (capability='$capability')"
    printf 'cpu\n'
    return 0
  fi

  # Interactive prompt when TTY available
  if [[ -t 0 ]]; then
    echo >&2
    echo "  ┌─────────────────────────────────────────────────────────┐" >&2
    echo "  │  Detected GPU: ${GPU_NAME}" >&2
    [[ -n "$GPU_MEM" ]] && echo "  │  VRAM:          ${GPU_MEM}" >&2
    [[ -n "$GPU_DRIVER" ]] && echo "  │  Driver:        ${GPU_DRIVER}" >&2
    echo "  └─────────────────────────────────────────────────────────┘" >&2
    echo >&2
    echo "  Use this GPU for Ollama? (faster generation)" >&2
    echo "    [Y] GPU  — primary path; CPU used automatically if GPU start fails" >&2
    echo "    [n] CPU  — skip GPU for this run" >&2
    printf "  Choice [Y/n]: " >&2
    read -r ans || true
    # Accept Y, y, yes, YES, empty (default Y), gpu
    case "${ans:-Y}" in
      n|N|no|NO|cpu|CPU) pref=cpu ;;
      *) pref=gpu ;;
    esac
    ok "Selected: $pref  (device: ${GPU_NAME})"
    printf '%s\n' "$pref"
    return 0
  fi

  # Non-interactive (no TTY): --yes / FULL_YES / default → GPU when capable
  if [[ "${FULL_YES:-0}" == "1" || "${RUN_FULL_YES:-}" == "1" ]]; then
    pref=gpu
    ok "Non-interactive --yes: using GPU for ${GPU_NAME}"
  else
    pref=gpu
    ok "No TTY — defaulting to gpu for ${GPU_NAME} (override: GPU_PREFERENCE=cpu)"
  fi
  printf '%s\n' "$pref"
}

capability="$(detect_gpu_capability | tr -d '[:space:]')"
printf '%s\n' "$capability" > "$STATUS_FILE"
ok "wrote .gpu_status=$capability"

preference="$(resolve_gpu_preference "$capability" | tr -d '[:space:]')"
printf '%s\n' "$preference" > "$PREF_FILE"
ok "wrote .gpu_preference=$preference"

echo "=== GPU: ${GPU_NAME} | CAPABILITY: $capability | PREFERENCE: $preference ===" >&2
