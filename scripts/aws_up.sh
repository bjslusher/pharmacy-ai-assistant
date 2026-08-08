#!/usr/bin/env bash
# Plan / apply / destroy — S3 + IAM + ALB + ASG. Preflight always first.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# shellcheck disable=SC1091
source "$ROOT/scripts/status_ui.sh"

ACTION="${1:-plan}"
PREFLIGHT="$ROOT/scripts/aws_preflight.sh"

if [[ ! -f "$PREFLIGHT" ]]; then
  ui_fail "missing $PREFLIGHT"
  exit 1
fi

ui_banner "AWS / Terraform — $ACTION"

ui_section "Preflight"
# shellcheck disable=SC1090
source "$PREFLIGHT"
aws_preflight_run
ui_ok "AWS preflight passed"

PROFILE="${AWS_PROFILE:-}"
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
ui_ok "profile=${PROFILE:-<default-chain>}  region=$REGION"

cd "$ROOT/terraform"

ui_section "Terraform init"
if terraform init -input=false -upgrade; then
  ui_ok "terraform init"
else
  ui_fail "terraform init"
  exit 1
fi

ui_section "Terraform validate"
if terraform validate; then
  ui_ok "terraform validate"
else
  ui_fail "terraform validate"
  exit 1
fi

VAR_ARGS=(-var="aws_profile=${PROFILE}" -var="aws_region=${REGION}")

case "$ACTION" in
  plan)
    ui_section "Terraform plan"
    terraform plan -input=false "${VAR_ARGS[@]}"
    ui_ok "terraform plan complete"
    echo "  Next: bash scripts/aws_up.sh apply"
    ;;
  apply)
    ui_section "Terraform apply"
    ui_wait "creating/updating S3, IAM, ALB, target groups, ASG, launch template…"
    if terraform apply -input=false -auto-approve "${VAR_ARGS[@]}"; then
      ui_ok "terraform apply"
    else
      ui_fail "terraform apply"
      exit 1
    fi

    ui_section "AWS components (from state)"
    # Best-effort component checklist from outputs
    if DATA=$(terraform output -raw s3_data_bucket 2>/dev/null); then
      ui_ok "S3 data bucket     $DATA"
    else
      ui_warn "S3 data bucket     (no output)"
    fi
    if LOGS=$(terraform output -raw s3_logs_bucket 2>/dev/null); then
      ui_ok "S3 logs bucket     $LOGS"
    else
      ui_warn "S3 logs bucket     (no output)"
    fi
    if ASG=$(terraform output -raw asg_name 2>/dev/null); then
      ui_ok "Auto Scaling Group $ASG"
    else
      ui_warn "Auto Scaling Group (no output)"
    fi
    if ALB=$(terraform output -raw alb_dns_name 2>/dev/null); then
      ui_ok "Application LB     $ALB"
      ui_ok "Frontend URL       http://$ALB"
      ui_ok "Health URL         http://$ALB/api/health"
    else
      ui_warn "ALB DNS            (no output)"
    fi
    ui_warn "ASG instances need 15–25+ min before target groups go healthy"

    echo
    terraform output
    ui_summary_box "STARTUP" \
      "${C_OK}✔${C_RST} Terraform apply succeeded" \
      "${C_OK}✔${C_RST} S3 / IAM / ALB / ASG present in state" \
      "${C_WARN}…${C_RST} EC2 user_data still booting Docker on instances"
    ;;
  destroy)
    ui_section "Terraform destroy (ASG first → no replacement instances)"
    ui_wait "destroying ALB, target groups, ASG/EC2, S3, IAM…"
    if terraform destroy -input=false -auto-approve "${VAR_ARGS[@]}"; then
      ui_ok "terraform destroy"
    else
      ui_fail "terraform destroy"
      exit 1
    fi

    ui_section "Post-destroy verification"
    # State should be empty
    LEFT=$(terraform state list 2>/dev/null || true)
    if [[ -z "${LEFT}" ]]; then
      ui_down "terraform state     empty (all managed resources gone)"
    else
      ui_fail "terraform state still has:"
      echo "$LEFT"
    fi
    ui_down "Application LB"
    ui_down "Target groups"
    ui_down "Auto Scaling Group (will not launch new EC2)"
    ui_down "Launch template / EC2"
    ui_down "S3 data + logs buckets"
    ui_down "IAM instance role/profile"

    ui_summary_box "SHUTDOWN" \
      "${C_OK}✔${C_RST} terraform destroy completed" \
      "${C_OK}✔${C_RST} ASG deleted — no auto-replacement of instances" \
      "${C_OK}✔${C_RST} ALB / S3 / IAM removed from this stack"
    ;;
  output)
    terraform output
    ;;
  preflight)
    ui_ok "preflight-only run finished"
    ;;
  *)
    echo "Usage: $0 [preflight|plan|apply|destroy|output]" >&2
    exit 1
    ;;
esac
