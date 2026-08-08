# AWS preflight (fail-fast)

Long steps (Docker image builds, Ollama pulls, EC2 `user_data`) must **not** run until AWS is known-good.

## Commands

```bash
# Checks only — finishes in a few seconds
bash scripts/aws_preflight.sh
bash scripts/run.sh aws preflight

# Preflight is automatic before plan/apply/destroy
bash scripts/run.sh aws plan
bash scripts/run.sh aws apply
```

## What is checked (in order)

| # | Check | Failure means |
|---|--------|----------------|
| 1 | `python3` + profile detector script | Install python3 |
| 2 | **AWS CLI** installed | Install AWS CLI v2 |
| 3 | **Terraform** ≥ 1.5 installed | Install Terraform |
| 4 | Local profiles (`brian` → `default`) | `aws configure --profile default` |
| 5 | `~/.aws` files or env keys present | Configure credentials |
| 6 | **`sts get-caller-identity`** | Bad/expired keys or SSO session |
| 7 | **EC2 API** `describe-regions` | Wrong region/network/permissions |
| 8 | **S3 API** `list-buckets` | Missing S3 permissions for apply |
| 9 | `terraform/` + `user_data.sh.tpl` + seed `.txt` files | Repo incomplete / wrong cwd |

On failure the script prints **`[FAIL]`** lines and exits **1** before `terraform init` or `apply`.

## Success looks like

```text
=== AWS preflight (fail-fast) ===
  [OK]  python3: ...
  [OK]  aws cli: ...
  [OK]  terraform: ...
  [OK]  using profile: default
  [OK]  region: us-east-1
  [OK]  account: 123456789012
  [OK]  identity: arn:aws:iam::...:user/...
  [OK]  EC2 API reachable ...
  [OK]  S3 API reachable ...
  [OK]  seed docs ready ...
=== PREFLIGHT PASSED — safe to plan/apply ===
```

## Typical fixes

| Message | Fix |
|---------|-----|
| AWS CLI not found | Install CLI; restart WSL shell |
| sts get-caller-identity failed | `aws configure --profile default` or `aws sso login` |
| no ~/.aws credentials | Create access keys in IAM console, configure locally |
| S3 list-buckets failed | Attach `AmazonS3FullAccess` (or tighter custom policy) for lab user |
| terraform not found | Install Terraform 1.5+ |

Only after preflight passes should you run **apply** (which creates resources and starts the slow EC2 bootstrap).
