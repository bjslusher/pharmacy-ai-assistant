#!/usr/bin/env bash
# Spin up / plan Pharmacy AI AWS infra using a detected local profile (brian or default).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DETECT="$ROOT/scripts/detect_aws_profile.py"
if [[ ! -f "$DETECT" ]]; then
  echo "Missing $DETECT" >&2
  exit 1
fi

echo "=== Scanning local AWS profiles (~/.aws) ==="
python3 "$DETECT" --list || true
echo

# shellcheck disable=SC2046
eval $(python3 "$DETECT" --export)

PROFILE="${AWS_PROFILE:-}"
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"

echo "=== Terraform with profile='${PROFILE:-<default chain>}' region='$REGION' ==="
cd "$ROOT/terraform"

terraform init -input=false

if [[ "${1:-plan}" == "apply" ]]; then
  terraform apply -input=false \
    -var="aws_profile=${PROFILE}" \
    -var="aws_region=${REGION}"
else
  terraform plan -input=false \
    -var="aws_profile=${PROFILE}" \
    -var="aws_region=${REGION}"
fi
