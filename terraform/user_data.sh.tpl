#!/bin/bash
set -euxo pipefail
exec > >(tee /var/log/pharmacy-ai-bootstrap.log | logger -t pharmacy-ai -s 2>/dev/console) 2>&1

echo "=== Pharmacy AI Assistant bootstrap starting ==="
export DEBIAN_FRONTEND=noninteractive
export AWS_DEFAULT_REGION="${aws_region}"
DATA_BUCKET="${data_bucket}"
LOGS_BUCKET="${logs_bucket}"
APP_DIR="/opt/${project_name}"

# ---- packages ----
apt-get update -y
apt-get install -y ca-certificates curl gnupg git jq unzip

# Docker
if ! command -v docker >/dev/null 2>&1; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  systemctl enable --now docker
fi

# AWS CLI v2
if ! command -v aws >/dev/null 2>&1; then
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
  unzip -q /tmp/awscliv2.zip -d /tmp
  /tmp/aws/install
fi

echo "=== Identity (instance role) ==="
aws sts get-caller-identity || true

echo "=== Clone application ==="
rm -rf "$APP_DIR"
git clone --depth 1 --branch "${git_branch}" "${git_repo_url}" "$APP_DIR"
cd "$APP_DIR"

echo "=== Sync knowledge base FROM S3 (required at startup) ==="
mkdir -p "$APP_DIR/backend/source_data"
aws s3 sync "s3://$${DATA_BUCKET}/source_data/" "$APP_DIR/backend/source_data/" --region "$AWS_DEFAULT_REGION"
ls -la "$APP_DIR/backend/source_data/"

# Prove write path works — heartbeat object
echo "boot $(date -Is) host $(hostname)" | aws s3 cp - "s3://$${DATA_BUCKET}/bootstrap/last_boot.txt" --region "$AWS_DEFAULT_REGION"
echo "bootstrap ok" | aws s3 cp - "s3://$${LOGS_BUCKET}/ec2/$(hostname)-boot.txt" --region "$AWS_DEFAULT_REGION"

# Env for compose / app
cat > "$APP_DIR/backend/.env" <<EOF
LLM_PROVIDER=ollama
OLLAMA_BASE_URL=http://ollama:11434
OLLAMA_MODEL=${ollama_model}
OLLAMA_EMBED_MODEL=${ollama_embed}
AWS_REGION=${aws_region}
AWS_DEFAULT_REGION=${aws_region}
S3_DATA_BUCKET=$${DATA_BUCKET}
S3_LOGS_BUCKET=$${LOGS_BUCKET}
DATA_PATH=/app/source_data
CHROMA_PATH=/app/chroma_db
EOF

echo "=== Docker Compose up ==="
cd "$APP_DIR"
docker compose up --build -d

echo "=== Pull Ollama models (may take several minutes) ==="
sleep 8
docker compose exec -T ollama ollama pull "${ollama_model}" || true
docker compose exec -T ollama ollama pull "${ollama_embed}" || true

echo "=== Wait for API health ==="
for i in $(seq 1 60); do
  if curl -sf http://127.0.0.1:8000/api/health >/dev/null; then
    curl -s http://127.0.0.1:8000/api/health | tee /tmp/health.json
    aws s3 cp /tmp/health.json "s3://$${LOGS_BUCKET}/ec2/health-first.json" || true
    break
  fi
  sleep 5
done

echo "=== Bootstrap complete ==="
