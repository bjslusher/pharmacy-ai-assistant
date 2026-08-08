#!/usr/bin/env bash
# Plan / apply / destroy Pharmacy AI AWS infra (EC2 + S3 + IAM).
# ALWAYS runs preflight first — fails in seconds if AWS is misconfigured.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ACTION="${1:-plan}"
PREFLIGHT="$ROOT/scripts/aws_preflight.sh"

if [[ ! -f "$PREFLIGHT" ]]; then
  echo "ERROR: missing $PREFLIGHT" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 1. Fail-fast AWS checks (before terraform init / apply)
# ---------------------------------------------------------------------------
# shellcheck disable=SC1090
source "$PREFLIGHT"
aws_preflight_run

PROFILE="${AWS_PROFILE:-}"
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"

echo
echo "=== Terraform $ACTION  profile='${PROFILE:-<default chain>}'  region='$REGION' ==="
cd "$ROOT/terraform"

# ---------------------------------------------------------------------------
# 2. Init (still relatively fast; only after preflight)
# ---------------------------------------------------------------------------
echo "=== terraform init ==="
if ! terraform init -input=false -upgrade; then
  echo "ERROR: terraform init failed. Check network and provider downloads." >&2
  exit 1
fi

echo "=== terraform validate ==="
if ! terraform validate; then
  echo "ERROR: terraform validate failed. Fix .tf syntax before apply." >&2
  exit 1
fi

VAR_ARGS=(-var="aws_profile=${PROFILE}" -var="aws_region=${REGION}")

# ---------------------------------------------------------------------------
# 3. Plan / apply / destroy
# ---------------------------------------------------------------------------
case "$ACTION" in
  plan)
    terraform plan -input=false "${VAR_ARGS[@]}"
    echo
    echo "Plan OK. When ready to create Free Tier–oriented EC2 + S3:"
    echo "  bash scripts/aws_up.sh apply"
    ;;
  apply)
    echo "=== terraform apply (creates S3 + IAM + EC2; user_data is long — preflight already passed) ==="
    terraform apply -input=false -auto-approve "${VAR_ARGS[@]}"
    echo
    echo "=== Outputs ==="
    terraform output
    echo
    echo "Wait 10–20 minutes on t3.micro for user_data (Docker + model pull). Then:"
    IP=$(terraform output -raw instance_public_ip 2>/dev/null || true)
    if [[ -n "$IP" ]]; then
      DATA=$(terraform output -raw s3_data_bucket 2>/dev/null || true)
      echo "  curl -s http://$IP:8000/api/health | jq"
      echo "  open http://$IP:3000"
      [[ -n "$DATA" ]] && echo "  aws s3 ls s3://$DATA/source_data/"
    fi
    ;;
  destroy)
    echo "=== terraform destroy ==="
    terraform destroy -input=false -auto-approve "${VAR_ARGS[@]}"
    ;;
  output)
    terraform output
    ;;
  preflight)
    # already ran
    echo "Preflight only — done."
    ;;
  *)
    echo "Usage: $0 [preflight|plan|apply|destroy|output]" >&2
    exit 1
    ;;
esac
