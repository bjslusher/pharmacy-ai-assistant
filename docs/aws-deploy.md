# AWS deploy — EC2 + S3 (required path)

This project creates **real AWS resources** when you run apply:

| Resource | Purpose |
|----------|---------|
| **S3 data bucket** | Stores seed knowledge (`source_data/*.txt`). EC2 **syncs from this bucket at first boot**. |
| **S3 logs bucket** | S3 access logs + bootstrap/health markers written by EC2. |
| **IAM role + instance profile** | EC2 can `s3:GetObject` / `PutObject` on those buckets without static keys. |
| **Security group** | SSH 22, UI 80/3000, API 8000. |
| **EC2 instance** | Ubuntu + Docker Compose stack (backend, frontend, Ollama). |

## Local apply (WSL2 / laptop)

```bash
# 1. Profiles (prefers brian, then default)
python3 scripts/detect_aws_profile.py --list

# 2. Plan (no cost beyond API calls)
bash scripts/aws_up.sh plan

# 3. Apply — creates S3 + EC2 + IAM + uploads seed objects
bash scripts/aws_up.sh apply

# 4. Note outputs
cd terraform && terraform output
```

Optional `terraform.tfvars`:

```hcl
key_name     = "your-keypair-name"   # for SSH
instance_type = "t3.medium"
aws_region   = "us-east-1"
```

## What happens on EC2 at startup (`user_data`)

1. Install Docker Engine + Compose plugin + AWS CLI v2  
2. `git clone` this repository  
3. **`aws s3 sync s3://DATA_BUCKET/source_data/` → `backend/source_data/`**  
4. Write boot heartbeat to S3 (`bootstrap/last_boot.txt`, logs bucket)  
5. `docker compose up --build -d`  
6. `ollama pull` chat + embed models  
7. Wait for `/api/health`; upload health JSON to logs bucket  

Bootstrap log on instance: `/var/log/pharmacy-ai-bootstrap.log`

## Verify after apply

```bash
IP=$(cd terraform && terraform output -raw instance_public_ip)
DATA=$(cd terraform && terraform output -raw s3_data_bucket)

# S3 seed present
aws s3 ls "s3://$DATA/source_data/"

# Wait for bootstrap (5–15+ min first time)
curl -s "http://$IP:8000/api/health" | jq

# UI
# open http://$IP:3000
```

## Destroy (stop charges)

```bash
bash scripts/aws_up.sh destroy
```

`force_destroy_buckets = true` (default) lets Terraform empty and delete the buckets.

## Console checklist

- **S3**: two buckets `pharmacy-ai-assistant-data-*` and `*-logs-*`  
- **S3 → data → source_data/**: imprint + DEA txt objects  
- **EC2**: instance running, instance profile attached  
- **IAM**: role `pharmacy-ai-assistant-ec2-role-*`  
- **Security groups**: ports 22, 80, 3000, 8000  

## Cost note

t3.medium + 40 GB gp3 + S3 storage + egress. Destroy when the demo is over.
