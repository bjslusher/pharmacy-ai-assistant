# AWS deploy — EC2 + S3 (Free Tier–first)

This project creates **real AWS resources** when you run apply. Defaults target **AWS Free Tier** where possible.

| Resource | Purpose | Free Tier notes |
|----------|---------|-----------------|
| **S3 data bucket** | Seed knowledge (`source_data/*.txt`). EC2 **syncs from this bucket at first boot**. | 5 GB standard storage is plenty for seed txt files |
| **S3 logs bucket** | Access logs + bootstrap/health markers | Same S3 free storage pool |
| **IAM role + instance profile** | EC2 reads/writes buckets without static keys | IAM is free |
| **Security group** | SSH 22, UI 80/3000, API 8000 | Free |
| **EC2 `t3.micro`** | Ubuntu + Docker Compose (backend, frontend, Ollama) | **750 hrs/mo** of t2.micro/t3.micro for eligible 12‑month accounts |
| **EBS 30 GB gp3** | Root volume | **30 GB** of GP storage is the usual Free Tier cap |

> Always confirm current Free Tier terms in your account: https://aws.amazon.com/free/

## Defaults (cost-conscious)

| Setting | Default | Why |
|---------|---------|-----|
| `instance_type` | `t3.micro` | Free Tier eligible |
| `root_volume_gb` | `30` | Matches typical Free Tier EBS allowance |
| `ollama_model` | `llama3.2:1b` | Fits micro RAM/disk better than full `llama3` |
| `ollama_embed_model` | `nomic-embed-text` | Small embed model |
| Region | `us-east-1` | Common Free Tier AMI availability |

**Tradeoff:** On `t3.micro`, answers can be slow and memory-tight. For a polished live demo after Free Tier limits, bump to `t3.small` / `t3.medium` and `llama3` via tfvars.

## Local apply (WSL2 / laptop)

```bash
# 1. Profiles (prefers brian, then default)
python3 scripts/detect_aws_profile.py --list

# 2. Plan (no EC2 charge until apply)
bash scripts/aws_up.sh plan

# 3. Apply Free Tier defaults
bash scripts/aws_up.sh apply

# Or force the free-tier file explicitly:
# cd terraform && terraform apply -var-file=free-tier.tfvars \
#   -var="aws_profile=$AWS_PROFILE" -var="aws_region=us-east-1"

# 4. Outputs
cd terraform && terraform output
```

Optional `terraform.tfvars`:

```hcl
key_name      = "your-keypair-name"
instance_type = "t3.micro"
root_volume_gb = 30
ollama_model  = "llama3.2:1b"
aws_region    = "us-east-1"
```

## What happens on EC2 at startup (`user_data`)

1. Install Docker Engine + Compose plugin + AWS CLI v2  
2. `git clone` this repository  
3. **`aws s3 sync s3://DATA_BUCKET/source_data/` → `backend/source_data/`**  
4. Write boot heartbeat to S3  
5. `docker compose up --build -d`  
6. `ollama pull` **small** chat model + embed model  
7. Wait for `/api/health`; upload health JSON to logs bucket  

Bootstrap log: `/var/log/pharmacy-ai-bootstrap.log`

## Verify after apply

```bash
IP=$(cd terraform && terraform output -raw instance_public_ip)
DATA=$(cd terraform && terraform output -raw s3_data_bucket)

aws s3 ls "s3://$DATA/source_data/"

# First boot can take 10–20+ minutes on t3.micro (builds + model pull)
curl -s "http://$IP:8000/api/health" | jq
# UI: http://$IP:3000
```

## Destroy (stop all ongoing charges)

```bash
bash scripts/aws_up.sh destroy
```

Even Free Tier accounts should destroy demos you are not using so hours/disk do not surprise you after eligibility ends.

## Console checklist

- **S3**: `pharmacy-ai-assistant-data-*` and `*-logs-*`  
- **S3 → data → source_data/**: imprint + DEA txt objects  
- **EC2**: **t3.micro**, instance profile attached  
- **EBS**: **30 GB** root  
- **IAM**: role `pharmacy-ai-assistant-ec2-role-*`  
- **Security groups**: 22, 80, 3000, 8000  

## When to leave Free Tier

| Symptom | Change |
|---------|--------|
| OOM / container restarts | `instance_type = "t3.small"` or `t3.medium` |
| Disk full pulling models | `root_volume_gb = 40` (billable over 30 GB) |
| Quality too low | `ollama_model = "llama3"` on a larger instance |

## Cost note

Free Tier is **not permanent** and **not unlimited**. Public IPv4 addresses may incur charges on newer accounts. Destroy when the assessment demo is finished.
