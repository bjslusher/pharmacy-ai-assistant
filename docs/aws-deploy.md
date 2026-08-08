# AWS deploy — S3 + ALB + Auto Scaling (demo)

Terraform creates a **demo-scale** production-shaped stack: knowledge in **S3**, compute in an **Auto Scaling Group**, traffic through an **Application Load Balancer**.

| Resource | Purpose | Notes |
|----------|---------|--------|
| **S3 data** | Seed `source_data/*.txt`; instances **sync at boot** | Private, encrypted |
| **S3 logs** | Access + bootstrap markers | Private |
| **IAM instance profile** | EC2 ↔ S3 without static keys | |
| **Launch template** | AMI, type, user_data, SG | Same Docker stack as local |
| **ASG** | `min=1`, `desired=1`, `max=2` | CPU target-tracking policy for scale demo |
| **ALB** | Public HTTP :80 | Path `/api/*` → backend :8000; default → frontend :3000 |
| **Target groups** | Frontend + backend health checks | Backend: `/api/health` |

> **Cost:** ALB is **not** Free Tier. EC2 `t3.micro` hours may be. Destroy when the demo ends: `bash scripts/run.sh stop --yes`

## Defaults

| Setting | Default |
|---------|---------|
| `instance_type` | `t3.micro` |
| `root_volume_gb` | `30` |
| `asg_min_size` / `desired` / `max` | `1` / `1` / `2` |
| `asg_health_check_grace_seconds` | `1200` (20 min for Docker + models) |
| `ollama_model` | `llama3.2:1b` |

## Apply

```bash
bash scripts/run.sh aws preflight
bash scripts/run.sh aws plan
bash scripts/run.sh aws apply
# or: bash scripts/run.sh full --yes
```

## After apply — instructor checklist

1. **EC2 → Auto Scaling Groups** — group `pharmacy-ai-assistant-asg-*`, desired 1  
2. **EC2 → Load Balancing → Load Balancers** — application LB  
3. **Target groups** — frontend :3000, backend :8000 (healthy after bootstrap)  
4. **S3** — data + logs buckets; `source_data/` objects  
5. Browser: `terraform output frontend_url` → UI via ALB  
6. `curl $(terraform output -raw health_url)` → JSON health  

Bootstrap is still slow on micro (15–25+ minutes). Grace period is 20 minutes so ASG does not thrash during first boot.

## Sequential stop

```bash
bash scripts/run.sh stop          # prompts before AWS destroy
bash scripts/run.sh stop --yes    # local Docker down, then terraform destroy
```

Order: **(1)** `docker compose down` → **(2)** `terraform destroy` (ALB, ASG/EC2, S3, IAM).

## Architecture sketch

```text
Internet → ALB :80
             ├─ /api/*  → TG backend  → ASG instances :8000  (FastAPI)
             └─ /*      → TG frontend → ASG instances :3000  (nginx UI)

ASG instances (1–2):
  user_data → git clone → s3 sync source_data → docker compose
  (backend + frontend + ollama)
```
