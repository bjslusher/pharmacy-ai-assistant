# Security & sensitive data

## What must never appear in logs or screenshots

| Item | Policy |
|------|--------|
| `AWS_SECRET_ACCESS_KEY` | Never print |
| `AWS_SESSION_TOKEN` | Never print |
| Private keys (`.pem`) | Never print / gitignored |
| `OPENAI_API_KEY`, `MEM0_API_KEY`, `LANGCHAIN_API_KEY` | Env only; never log values |
| Full AWS account ID | Masked in preflight (`****4728`) |
| Full IAM ARN | Masked (`…user/B***`) |
| Access key ID (`AKIA…`) | Partial mask only |

## Where masking is applied

- `scripts/aws_preflight.sh` — STS account + ARN + env key presence
- `scripts/redact.sh` — shared helpers for other scripts

Opt-in full identity (private machine only):

```bash
export AWS_PREFLIGHT_SHOW_IDENTITY=1
```

## Repo hygiene

- `.env` and `backend/.env` are gitignored
- `*.tfstate`, `*.tfvars` (except examples), `*.pem` gitignored
- GitHub Actions should use repository **Secrets**, not hard-coded keys
- Terraform outputs expose public URLs/bucket names (expected); not IAM user ARNs

## If you already leaked an account ID in a screenshot

Account IDs are not secret keys, but avoid publishing them. Rotate access keys if a **secret** key was ever pasted into chat, slides, or a public gist.
