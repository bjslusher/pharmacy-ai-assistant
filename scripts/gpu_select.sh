#!/usr/bin/env bash
# GPU detect + preference. Logs on stderr; helpers print only gpu|cpu on stdout.
# Priority: GPU_PREFERENCE env > FULL_YES/--yes > interactive prompt > saved file > default gpu
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
STATUS_FILE="$ROOT/.gpu_status"
PREF_FILE="$ROOT/.gpu_preference"
NAME_FILE="$ROOT/.gpu_name"

ok()   { echo "  [OK]  $*" >&2; }
warn() { echo "  [WARN] $*" >&2; }

GPU_NAME="(none)"
GPU_MEM=""
GPU_DRIVER=""

detect_gpu_capability() {
  local host_gpu=0 docker_gpu=0
  GPU_NAME="(none)"; GPU_MEM=""; GPU_DRIVER=""

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
    warn "No working nvidia-smi on host"
  fi

  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    if docker info 2>/dev/null | grep -qiE 'Runtimes:.*nvidia|nvidia'; then
      docker_gpu=1; ok "Docker NVIDIA runtime / capability reported"
    else
      warn "Docker does not report NVIDIA runtime"
    fi
  fi

  # Persist name for parent shell / preflight banner (survives subshell)
  printf '%s\n' "$GPU_NAME" > "$NAME_FILE"
  {
    echo "GPU_NAME=${GPU_NAME}"
    echo "GPU_MEM=${GPU_MEM}"
    echo "GPU_DRIVER=${GPU_DRIVER}"
  } > "$ROOT/.gpu_info.env"

  if [[ "$host_gpu" -eq 1 && "$docker_gpu" -eq 1 ]]; then printf 'gpu\n'
  elif [[ "$host_gpu" -eq 1 ]]; then
    warn "${GPU_NAME} on host; Docker may not pass GPU — CPU fallback if compose fails"
    printf 'gpu\n'
  else printf 'cpu\n'
  fi
}

resolve_gpu_preference() {
  local capability; capability="$(echo "$1" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
  local pref=""

  # Reload name from file (parent may have lost subshell vars)
  if [[ -f "$NAME_FILE" ]]; then
    GPU_NAME="$(tr -d '\n' < "$NAME_FILE")"
  fi
  if [[ -f "$ROOT/.gpu_info.env" ]]; then
    # shellcheck disable=SC1091
    source "$ROOT/.gpu_info.env" 2>/dev/null || true
  fi

  # 1) Explicit env always wins
  if [[ -n "${GPU_PREFERENCE:-}" ]]; then
    pref="$(echo "$GPU_PREFERENCE" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  elif [[ -n "${GPU_MODE:-}" ]]; then
    pref="$(echo "$GPU_MODE" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  fi
  if [[ "$pref" == "gpu" || "$pref" == "cpu" ]]; then
    ok "GPU preference from environment: $pref"
    printf '%s\n' "$pref"; return 0
  fi

  # 2) No hardware → cpu
  if [[ "$capability" != "gpu" ]]; then
    warn "No usable GPU — locking preference to cpu"
    printf 'cpu\n'; return 0
  fi

  # 3) --yes / FULL_YES: GPU when capable — OVERRIDES stale .gpu_preference=cpu
  if [[ "${FULL_YES:-0}" == "1" || "${RUN_FULL_YES:-}" == "1" ]]; then
    ok "--yes / FULL_YES: using GPU for ${GPU_NAME} (overriding any saved preference)"
    printf 'gpu\n'; return 0
  fi

  # 4) Interactive prompt (FORCE_GPU_PROMPT or no saved file)
  if [[ "${FORCE_GPU_PROMPT:-0}" == "1" || ! -f "$PREF_FILE" ]]; then
    if [[ -t 0 ]]; then
      echo >&2
      echo "  ┌─────────────────────────────────────────────────────────┐" >&2
      echo "  │  Detected GPU: ${GPU_NAME}" >&2
      [[ -n "${GPU_MEM:-}" ]] && echo "  │  VRAM:          ${GPU_MEM}" >&2
      [[ -n "${GPU_DRIVER:-}" ]] && echo "  │  Driver:        ${GPU_DRIVER}" >&2
      echo "  └─────────────────────────────────────────────────────────┘" >&2
      echo >&2
      echo "  Use this GPU for Ollama? (faster generation)" >&2
      echo "    [Y] / yes / Enter  → GPU (CPU auto-fallback if start fails)" >&2
      echo "    [n] / no          → CPU only" >&2
      printf "  Choice [Y/n]: " >&2
      read -r ans || true
      case "${ans:-Y}" in
        n|N|no|NO|cpu|CPU) pref=cpu ;;
        *) pref=gpu ;;
      esac
      ok "Selected: $pref  (device: ${GPU_NAME})"
      printf '%s\n' "$pref"; return 0
    fi
  fi

  # 5) Saved preference (only if not forced and not --yes)
  if [[ -f "$PREF_FILE" ]]; then
    pref="$(tr -d '[:space:]' < "$PREF_FILE" | tr '[:upper:]' '[:lower:]')"
    if [[ "$pref" == "gpu" || "$pref" == "cpu" ]]; then
      if [[ "$pref" == "cpu" && "$capability" == "gpu" ]]; then
        warn "Saved preference is cpu but ${GPU_NAME} is available."
        warn "  Re-ask: FORCE_GPU_PROMPT=1 bash scripts/run.sh start"
        warn "  Or force: GPU_PREFERENCE=gpu bash scripts/run.sh start"
        warn "  Or delete: rm -f .gpu_preference"
      fi
      ok "GPU preference from .gpu_preference: $pref"
      printf '%s\n' "$pref"; return 0
    fi
  fi

  # 6) Default when GPU capable: gpu
  ok "Defaulting to gpu for ${GPU_NAME}"
  printf 'gpu\n'
}

capability="$(detect_gpu_capability | tr -d '[:space:]')"
printf '%s\n' "$capability" > "$STATUS_FILE"
ok "wrote .gpu_status=$capability"

# Restore name after subshell
if [[ -f "$NAME_FILE" ]]; then
  GPU_NAME="$(tr -d '\n' < "$NAME_FILE")"
fi
if [[ -f "$ROOT/.gpu_info.env" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT/.gpu_info.env" 2>/dev/null || true
fi

preference="$(resolve_gpu_preference "$capability" | tr -d '[:space:]')"
printf '%s\n' "$preference" > "$PREF_FILE"
ok "wrote .gpu_preference=$preference"

echo "=== GPU: ${GPU_NAME} | CAPABILITY: $capability | PREFERENCE: $preference ===" >&2
