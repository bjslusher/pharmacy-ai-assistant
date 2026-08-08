# Preflight — all systems before long startup

The orchestrator **never** starts Docker builds, model pulls, or Terraform apply until preflight passes for that path.

## Commands

```bash
# Local Docker systems only
bash scripts/run.sh preflight
bash scripts/preflight.sh local

# AWS only (CLI, STS, EC2/S3 APIs, terraform files, seed)
bash scripts/run.sh aws preflight
bash scripts/preflight.sh aws

# Everything
bash scripts/run.sh preflight all
bash scripts/preflight.sh all

# Start local stack (runs local preflight automatically first)
bash scripts/run.sh

# AWS plan/apply (runs AWS preflight automatically first)
bash scripts/run.sh aws plan
bash scripts/run.sh aws apply
```

## Local checks

| Check | Purpose |
|--------|---------|
| Docker + Compose | Build/run stack |
| Docker daemon | Desktop/engine running |
| curl | Health probes |
| compose + Dockerfiles + backend sources | Repo intact |
| `backend/source_data/*.txt` | RAG seed present |
| Disk space | Images + models |
| Ports 3000 / 8000 / 11434 | Conflicts warned |
| python3 | Optional tests |

## AWS checks

Delegates to `scripts/aws_preflight.sh`:

- AWS CLI, Terraform, profile (`brian` → `default`)
- `sts get-caller-identity`
- EC2 + S3 API reachability
- terraform dir, user_data template, seed files for S3 upload

## Design

```text
run.sh start  → preflight local → docker compose up → models → health
run.sh aws *  → preflight aws   → terraform init/validate → plan|apply
```

If preflight fails, the process exits **before** any multi-minute work.
