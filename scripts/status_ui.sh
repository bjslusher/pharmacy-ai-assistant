#!/usr/bin/env bash
# Shared visual cues for orchestrator (sourced by run.sh / aws_up.sh)

if [[ -t 1 ]] && [[ "${NO_COLOR:-}" == "" ]]; then
  C_OK='\033[1;32m'
  C_FAIL='\033[1;31m'
  C_WARN='\033[1;33m'
  C_INFO='\033[1;36m'
  C_DIM='\033[2m'
  C_BOLD='\033[1m'
  C_RST='\033[0m'
else
  C_OK=''; C_FAIL=''; C_WARN=''; C_INFO=''; C_DIM=''; C_BOLD=''; C_RST=''
fi

ui_banner() {
  local title="$1"
  echo
  echo -e "${C_BOLD}╔════════════════════════════════════════════════════════════╗${C_RST}"
  printf "${C_BOLD}║ %-58s ║${C_RST}\n" "$title"
  echo -e "${C_BOLD}╚════════════════════════════════════════════════════════════╝${C_RST}"
}

ui_section() {
  echo
  echo -e "${C_INFO}── $1 ──${C_RST}"
}

ui_ok() {
  echo -e "  ${C_OK}✔  UP / OK${C_RST}     $1"
}

ui_down() {
  echo -e "  ${C_OK}✔  DOWN${C_RST}        $1"
}

ui_fail() {
  echo -e "  ${C_FAIL}✖  FAILED${C_RST}      $1" >&2
}

ui_warn() {
  echo -e "  ${C_WARN}⚠  WARN${C_RST}        $1"
}

ui_wait() {
  echo -e "  ${C_DIM}…  waiting${C_RST}     $1"
}

ui_skip() {
  echo -e "  ${C_DIM}–  skipped${C_RST}     $1"
}

ui_summary_box() {
  local kind="$1"
  shift
  echo
  if [[ "$kind" == "STARTUP" ]]; then
    echo -e "${C_OK}${C_BOLD}▶ STARTUP SUMMARY${C_RST}"
  else
    echo -e "${C_OK}${C_BOLD}■ SHUTDOWN SUMMARY${C_RST}"
  fi
  for line in "$@"; do
    echo -e "  $line"
  done
  echo
}

# Big obvious where-to-click block (always last thing users should see)
ui_access_box() {
  local local_fe="${1:-}"
  local local_api="${2:-}"
  local aws_fe="${3:-}"
  local aws_health="${4:-}"

  echo
  echo -e "${C_OK}${C_BOLD}"
  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║                                                            ║"
  echo "║   OPEN THE APP HERE                                        ║"
  echo "║                                                            ║"
  if [[ -n "$local_fe" ]]; then
    printf "║   LOCAL UI:   %-44s ║\n" "$local_fe"
  fi
  if [[ -n "$local_api" ]]; then
    printf "║   LOCAL API:  %-44s ║\n" "$local_api"
  fi
  if [[ -n "$aws_fe" ]]; then
    echo "║                                                            ║"
    printf "║   AWS UI:     %-44s ║\n" "$aws_fe"
  fi
  if [[ -n "$aws_health" ]]; then
    printf "║   AWS HEALTH: %-44s ║\n" "$aws_health"
  fi
  echo "║                                                            ║"
  echo "╚════════════════════════════════════════════════════════════╝"
  echo -e "${C_RST}"
  if [[ -n "$aws_fe" ]]; then
    echo -e "  ${C_WARN}AWS UI may take 15-25+ minutes after apply (Docker + models on EC2).${C_RST}"
    echo -e "  ${C_DIM}Until then use LOCAL UI above.${C_RST}"
  fi
  echo
}
