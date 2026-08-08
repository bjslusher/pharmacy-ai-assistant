# Security & sensitive data

Full policy for demos, screenshots, and repo hygiene. Also summarized in the root [README](../README.md#security-risks-and-mitigations).

## Risks and mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| Secret access key or session token printed in terminal | Critical | **Never printed.** Preflight only reports that the env var is present. |
| Access key ID (`AKIA…` / `ASIA…`) fully logged | High | Partial mask (`AKIA************XXXX`). Error text is scrubbed for key patterns. |
| Full 12-digit AWS account ID in screenshots | Medium | Default mask: `****` + last 4 digits. |
| Full IAM ARN with username | Medium | Masked account + shortened principal (`user/B***`). |
| `.env` / API keys committed to git | Critical | Gitignored: `.env`, `backend/.env`, `*.pem`, `*.tfstate`, real `*.tfvars`. |
| Secrets hard-coded in GitHub Actions YAML | Critical | Use repository Secrets (`${{ secrets.* }}`) only. |
| Terraform state committed | High | `*.tfstate*` gitignored; destroy via `run.sh stop`. |
| Third-party keys (OpenAI, Mem0, LangSmith) in logs | High | Optional env only; application code does not log values. |

## Console masking (default on)

```bash
bash scripts/aws_preflight.sh
# [OK] account: ****4728
# [OK] identity: arn:aws:iam::****4728:user/B***
```

Full identity (private machine only):

```bash
AWS_PREFLIGHT_SHOW_IDENTITY=1 bash scripts/aws_preflight.sh
# or: bash scripts/aws_preflight.sh --show-identity
```

Helpers: [`scripts/redact.sh`](../scripts/redact.sh) · wired from [`scripts/aws_preflight.sh`](../scripts/aws_preflight.sh).

## Repo checklist

- [ ] No real keys in commits (`git log -p` / secret scanners)
- [ ] Local `.env` never copied into slides or Discord
- [ ] Prefer masked preflight when recording demos
- [ ] `bash scripts/run.sh stop --yes` after AWS demos (cost + residual resources)

## If something already leaked

| Leaked | Action |
|--------|--------|
| Secret access key | Deactivate/delete key in IAM immediately; create a new one |
| Session token | Wait for expiry or revoke session; re-login |
| Account ID only | Low urgency; avoid further public posts of the same screenshot |
| Third-party API key | Rotate at the provider |
