#!/usr/bin/env bash
# Plan / apply / destroy Pharmacy AI AWS infra (S3 + IAM + ALB + ASG).
# ALWAYS runs preflight first.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ACTION="${1:-plan}"
PREFLIGHT="$ROOT/scripts/aws_preflight.sh"

if [[ ! -f "$PREFLIGHT" ]]; then
  echo "ERROR: missing $PREFLIGHT" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$PREFLIGHT"
aws_preflight_run

PROFILE="${AWS_PROFILE:-}"
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"

echo
echo "=== Terraform $ACTION  profile='${PROFILE:-<default chain>}'  region='$REGION' ==="
cd "$ROOT/terraform"

echo "=== terraform init ==="
if ! terraform init -input=false -upgrade; then
  echo "ERROR: terraform init failed." >&2
  exit 1
fi

echo "=== terraform validate ==="
if ! terraform validate; then
  echo "ERROR: terraform validate failed." >&2
  exit 1
fi

VAR_ARGS=(-var="aws_profile=${PROFILE}" -var="aws_region=${REGION}")

case "$ACTION" in
  plan)
    terraform plan -input=false "${VAR_ARGS[@]}"
    echo
    echo "Plan OK. Creates: S3, IAM, ALB, target groups, ASG (launch template + EC2)."
    echo "  bash scripts/aws_up.sh apply"
    ;;
  apply)
    echo "=== terraform apply (S3 + ALB + ASG; user_data is long) ==="
    terraform apply -input=false -auto-approve "${VAR_ARGS[@]}"
    echo
    echo "=== Outputs ==="
    terraform output
    echo
    ALB=$(terraform output -raw alb_dns_name 2>/dev/null || true)
    if [[ -n "$ALB" ]]; then
      echo "Preferred entrypoint (ALB):"
      echo "  UI:     http://$ALB"
      echo "  Health: http://$ALB/api/health"
      echo "  Docs:   http://$ALB/docs"
      echo "Wait 15–25+ min for first instance user_data + ALB health checks."
    fi
    ;;
  destroy)
    echo "=== terraform destroy (ALB → ASG/EC2 → S3 → IAM) ==="
    terraform destroy -input=false -auto-approve "${VAR_ARGS[@]}"
    echo "AWS resources destroyed."
    ;;
  output)
    terraform output
    ;;
  preflight)
    echo "Preflight only — done."
    ;;
  *)
    echo "Usage: $0 [preflight|plan|apply|destroy|output]" >&2
    exit 1
    ;;
esac
