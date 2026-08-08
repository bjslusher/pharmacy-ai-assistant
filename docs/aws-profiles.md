# AWS profile detection (local machine)

When you spin up AWS resources from **your laptop**, this project looks for named profiles in your local AWS config (typically `~/.aws/credentials` and `~/.aws/config`).

## Preferred profiles

Search order:

1. Environment: `AWS_PROFILE` or `AWS_DEFAULT_PROFILE` (if already set)
2. Named profile **`brian`**
3. Named profile **`default`** (common when the AWS CLI was configured with defaults)
4. First other profile found in `~/.aws`
5. Empty → AWS SDK default credential chain (env vars `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`, SSO, instance role, etc.)

Your note that local AWS CONFIG uses **default** is supported: the detector will select `default` when `brian` is not present.

## Quick usage

```bash
# See what the detector finds
python3 scripts/detect_aws_profile.py --list
python3 scripts/detect_aws_profile.py --json

# Export for this shell session
eval $(python3 scripts/detect_aws_profile.py --export)

# Plan (default) or apply
bash scripts/aws_up.sh
bash scripts/aws_up.sh apply
```

Terraform receives the profile via:

```hcl
provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile != "" ? var.aws_profile : null
}
```

## GitHub Actions

CI/Deploy on GitHub runners **do not** read your laptop’s `~/.aws`. There, use repository secrets:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION` (optional)

Local profile auto-detection is intentionally for developer machines only.

## Security

- Never commit `~/.aws/credentials` or real keys.
- `*.tfvars` with secrets stays gitignored; use `terraform.tfvars.example` as a template.
