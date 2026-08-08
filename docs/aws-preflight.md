# AWS preflight

Runs **before** Terraform plan/apply so bad credentials fail in seconds, not after a long bootstrap.

```bash
bash scripts/aws_preflight.sh
# or via orchestrator
bash scripts/run.sh full --yes   # includes AWS preflight
```

## Checks

| Step | What |
|------|------|
| 1 | python3 |
| 2 | AWS CLI |
| 3 | Terraform |
| 4 | Profile detection (`brian` / `default`) |
| 5 | Env key **presence** only (values never printed) |
| 6 | `sts get-caller-identity` (account/ARN **masked**) |
| 7 | EC2 + S3 API reachability |
| 8 | Terraform files + seed docs |

## Identity masking (default)

Console output **does not** show full account IDs or IAM ARNs:

```text
  [OK]  account: ****4728
  [OK]  identity: arn:aws:iam::****4728:user/B***
=== PREFLIGHT PASSED — safe to plan/apply ===
  profile=default region=us-east-1 account=****4728
```

Local debug only (do not use while screen-sharing):

```bash
AWS_PREFLIGHT_SHOW_IDENTITY=1 bash scripts/aws_preflight.sh
# or
bash scripts/aws_preflight.sh --show-identity
```

**Never printed:** `AWS_SECRET_ACCESS_KEY`, session tokens, private keys.

## Troubleshooting

| Message | Fix |
|---------|-----|
| sts get-caller-identity failed | `aws configure --profile default` or `aws sso login` |
| S3 list-buckets failed | IAM needs S3 permissions for apply |
| EC2 API not reachable | Region/permissions/network |
