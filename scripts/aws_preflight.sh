#!/usr/bin/env bash
# =============================================================================
# Pharmacy AI — AWS preflight (FAIL FAST before plan/apply/long bootstrap)
#
# Usage:
#   bash scripts/aws_preflight.sh
#   bash scripts/aws_preflight.sh --quiet
#   source scripts/aws_preflight.sh && aws_preflight_run
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DETECT="$ROOT/scripts/detect_aws_profile.py"
QUIET=0
DO_EXPORT=0

for arg in "$@"; do
  case "$arg" in
    --quiet|-q) QUIET=1 ;;
    --export) DO_EXPORT=1 ;;
    --help|-h)
      sed -n '2,12p' "$0"
      exit 0
      ;;
  esac
done

log()  { echo "$*"; }
info() { [[ "$QUIET" -eq 1 ]] || echo "  $*"; }
ok()   { echo "  [OK]  $*"; }
fail() { echo "  [FAIL] $*" >&2; }
warn() { echo "  [WARN] $*" >&2; }
die()  {
  echo >&2
  echo "=== PREFLIGHT FAILED — fix the item(s) above, then re-run ===" >&2
  echo "    bash scripts/aws_preflight.sh" >&2
  echo "    bash scripts/aws_up.sh plan" >&2
  exit 1
}

ERRORS=0
bump() { ERRORS=$((ERRORS + 1)); }

aws_preflight_run() {
  ERRORS=0
  log "=== AWS preflight (fail-fast) ==="

  # --- 1. Python ---
  if ! command -v python3 >/dev/null 2>&1; then
    fail "python3 not found (needed for profile detection)"
    bump
  else
    ok "python3: $(python3 --version 2>&1)"
  fi

  if [[ ! -f "$DETECT" ]]; then
    fail "Missing $DETECT"
    bump
  else
    ok "profile detector present"
  fi

  # --- 2. AWS CLI ---
  if ! command -v aws >/dev/null 2>&1; then
    fail "AWS CLI not found"
    info "Install: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    info "WSL: then run: aws configure --profile default"
    bump
  else
    ok "aws cli: $(aws --version 2>&1 | head -1)"
  fi

  # --- 3. Terraform ---
  if ! command -v terraform >/dev/null 2>&1; then
    fail "terraform not found (need >= 1.5)"
    info "Install: https://developer.hashicorp.com/terraform/install"
    bump
  else
    TFV=$(terraform version -json 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin).get("terraform_version","?"))' 2>/dev/null || terraform version | head -1)
    ok "terraform: $TFV"
  fi

  if [[ "$ERRORS" -gt 0 ]]; then
    die
  fi

  # --- 4. Profile discovery (no fragile eval of free-form text) ---
  log "--- Profiles ---"
  python3 "$DETECT" --list || true

  PROFILE="$(python3 "$DETECT" 2>/dev/null || true)"
  PROFILE="${PROFILE//$'\r'/}"
  PROFILE="${PROFILE//$'\n'/}"
  REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"

  export AWS_PROFILE="${PROFILE}"
  export AWS_REGION="$REGION"
  export AWS_DEFAULT_REGION="$REGION"
  export TF_VAR_aws_profile="${PROFILE}"
  export TF_VAR_aws_region="$REGION"

  if [[ -n "$PROFILE" ]]; then
    ok "using profile: $PROFILE"
  else
    warn "no named profile (brian/default) — using default credential chain (env keys / SSO)"
  fi
  ok "region: $REGION"

  # --- 5. Credentials file hints ---
  AWS_HOME="${AWS_SHARED_CREDENTIALS_FILE:-$HOME/.aws/credentials}"
  AWS_CFG="${AWS_CONFIG_FILE:-$HOME/.aws/config}"
  if [[ -f "$AWS_HOME" ]] || [[ -f "$AWS_CFG" ]]; then
    ok "~/.aws config/credentials found"
  else
    if [[ -z "${AWS_ACCESS_KEY_ID:-}" ]]; then
      fail "no ~/.aws credentials/config and AWS_ACCESS_KEY_ID unset"
      info "Run: aws configure --profile default   (or create profile 'brian')"
      bump
    else
      ok "AWS_ACCESS_KEY_ID present in environment"
    fi
  fi

  if [[ "$ERRORS" -gt 0 ]]; then
    die
  fi

  # --- 6. STS identity ---
  log "--- Credentials (STS) ---"
  STS_OUT=$(mktemp)
  STS_ERR=$(mktemp)
  set +e
  if [[ -n "$PROFILE" ]]; then
    aws sts get-caller-identity --profile "$PROFILE" --region "$REGION" >"$STS_OUT" 2>"$STS_ERR"
  else
    aws sts get-caller-identity --region "$REGION" >"$STS_OUT" 2>"$STS_ERR"
  fi
  STS_RC=$?
  set -e
  if [[ "$STS_RC" -ne 0 ]]; then
    fail "sts get-caller-identity failed (credentials invalid or expired)"
    sed 's/^/         /' "$STS_ERR" >&2 || true
    info "Fix: aws configure --profile ${PROFILE:-default}"
    info "  or refresh SSO: aws sso login --profile ${PROFILE:-default}"
    info "  or export AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY"
    rm -f "$STS_OUT" "$STS_ERR"
    bump
    die
  fi
  ACCOUNT=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["Account"])' "$STS_OUT")
  ARN=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["Arn"])' "$STS_OUT")
  ok "account: $ACCOUNT"
  ok "identity: $ARN"
  rm -f "$STS_OUT" "$STS_ERR"

  # --- 7. Region / EC2 / S3 ---
  log "--- Service reachability ---"
  set +e
  if [[ -n "$PROFILE" ]]; then
    aws ec2 describe-regions --region "$REGION" --profile "$PROFILE" --query 'Regions[0].RegionName' --output text >/dev/null 2>"$STS_ERR"
  else
    aws ec2 describe-regions --region "$REGION" --query 'Regions[0].RegionName' --output text >/dev/null 2>"$STS_ERR"
  fi
  EC2_RC=$?
  set -e
  if [[ "$EC2_RC" -ne 0 ]]; then
    fail "EC2 API not reachable in region $REGION (permissions or network)"
    bump
  else
    ok "EC2 API reachable in $REGION"
  fi

  set +e
  if [[ -n "$PROFILE" ]]; then
    aws s3api list-buckets --profile "$PROFILE" --region "$REGION" --max-items 1 >/dev/null 2>"$STS_ERR"
  else
    aws s3api list-buckets --region "$REGION" --max-items 1 >/dev/null 2>"$STS_ERR"
  fi
  S3_RC=$?
  set -e
  if [[ "$S3_RC" -ne 0 ]]; then
    fail "S3 list-buckets failed — IAM user/role needs s3 permissions for apply"
    info "Apply will create buckets; caller needs s3:CreateBucket, etc."
    bump
  else
    ok "S3 API reachable (list-buckets)"
  fi

  ok "IAM/STS path usable for instance profiles (full IAM checked at apply)"

  # --- 8. Terraform files + seed ---
  log "--- Terraform files ---"
  if [[ ! -d "$ROOT/terraform" ]]; then
    fail "missing $ROOT/terraform"
    bump
  else
    ok "terraform/ directory present"
  fi
  if [[ ! -f "$ROOT/terraform/main.tf" ]]; then
    fail "missing terraform/main.tf"
    bump
  else
    ok "main.tf present"
  fi
  if [[ ! -f "$ROOT/terraform/user_data.sh.tpl" ]]; then
    fail "missing terraform/user_data.sh.tpl (EC2 bootstrap)"
    bump
  else
    ok "user_data.sh.tpl present"
  fi
  SEED_COUNT=$(find "$ROOT/backend/source_data" -name '*.txt' 2>/dev/null | wc -l | tr -d ' ')
  if [[ "${SEED_COUNT:-0}" -lt 1 ]]; then
    fail "no seed .txt files under backend/source_data (S3 seed upload will be empty)"
    bump
  else
    ok "seed docs ready for S3 upload ($SEED_COUNT files)"
  fi

  if command -v terraform >/dev/null 2>&1; then
    if ! (cd "$ROOT/terraform" && terraform fmt -check -recursive >/dev/null 2>&1); then
      warn "terraform fmt would reformat files (non-blocking) — run: terraform fmt -recursive"
    else
      ok "terraform fmt clean"
    fi
  fi

  if [[ "$ERRORS" -gt 0 ]]; then
    die
  fi

  log "=== PREFLIGHT PASSED — safe to plan/apply ==="
  info "profile=${PROFILE:-<default-chain>} region=$REGION account=$ACCOUNT"
  info "next: bash scripts/aws_up.sh plan"
  info "then: bash scripts/aws_up.sh apply"
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  aws_preflight_run
  if [[ "$DO_EXPORT" -eq 1 ]]; then
    echo "export AWS_PROFILE=\"${AWS_PROFILE:-}\""
    echo "export AWS_REGION=\"${AWS_REGION:-us-east-1}\""
    echo "export AWS_DEFAULT_REGION=\"${AWS_DEFAULT_REGION:-us-east-1}\""
    echo "export TF_VAR_aws_profile=\"${TF_VAR_aws_profile:-}\""
    echo "export TF_VAR_aws_region=\"${TF_VAR_aws_region:-us-east-1}\""
  fi
fi
