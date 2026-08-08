#!/usr/bin/env bash
# Plan or apply Pharmacy AI AWS infra: EC2 + S3 data/logs + IAM + seed upload.
# S3 is used at EC2 startup (user_data syncs source_data from the data bucket).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DETECT="$ROOT/scripts/detect_aws_profile.py"
if [[ ! -f "$DETECT" ]]; then
  echo "Missing $DETECT" >&2
  exit 1
fi

if ! command -v terraform >/dev/null 2>&1; then
  echo "ERROR: terraform not found. Install Terraform >= 1.5." >&2
  exit 1
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "WARNING: aws CLI not found — profile detection may still work from ~/.aws files." >&2
fi

echo "=== Scanning local AWS profiles (~/.aws) ==="
python3 "$DETECT" --list || true
echo

# shellcheck disable=SC2046
eval $(python3 "$DETECT" --export)

PROFILE="${AWS_PROFILE:-}"
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
ACTION="${1:-plan}"

echo "=== Terraform $ACTION  profile='${PROFILE:-<default chain>}'  region='$REGION' ==="
cd "$ROOT/terraform"

terraform init -input=false -upgrade

VAR_ARGS=(-var="aws_profile=${PROFILE}" -var="aws_region=${REGION}")

case "$ACTION" in
  plan)
    terraform plan -input=false "${VAR_ARGS[@]}"
    echo
    echo "Review the plan. When ready to create EC2 + S3:"
    echo "  bash scripts/aws_up.sh apply"
    ;;
  apply)
    terraform apply -input=false -auto-approve "${VAR_ARGS[@]}"
    echo
    echo "=== Outputs ==="
    terraform output
    echo
    echo "Wait 5–15 minutes for user_data (Docker + model pull). Then:"
    IP=$(terraform output -raw instance_public_ip 2>/dev/null || true)
    if [[ -n "$IP" ]]; then
      echo "  curl -s http://$IP:8000/api/health | jq"
      echo "  open http://$IP:3000"
      echo "  aws s3 ls s3://$(terraform output -raw s3_data_bucket)/source_data/"
    fi
    ;;
  destroy)
    terraform destroy -input=false -auto-approve "${VAR_ARGS[@]}"
    ;;
  output)
    terraform output
    ;;
  *)
    echo "Usage: $0 [plan|apply|destroy|output]" >&2
    exit 1
    ;;
esac
