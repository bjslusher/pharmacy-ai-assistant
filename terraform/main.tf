terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Profile resolved on the machine that runs Terraform:
#   1) TF_VAR_aws_profile / -var aws_profile=...
#   2) scripts/detect_aws_profile.py  (prefers brian, then default)
#   3) empty → AWS SDK default chain
provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile != "" ? var.aws_profile : null
}

data "aws_caller_identity" "current" {}

resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  name_prefix = var.project_name
  bucket_data = lower("${var.project_name}-data-${random_id.suffix.hex}")
  bucket_logs = lower("${var.project_name}-logs-${random_id.suffix.hex}")
  common_tags = {
    Project     = var.project_name
    ManagedBy   = "terraform"
    Environment = var.environment
  }
}

# ---------------------------------------------------------------------------
# S3 — application data (seed docs, optional chroma export) + access logs
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "data" {
  bucket        = local.bucket_data
  force_destroy = var.force_destroy_buckets

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-data"
    Role = "app-data"
  })
}

resource "aws_s3_bucket" "logs" {
  bucket        = local.bucket_logs
  force_destroy = var.force_destroy_buckets

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-logs"
    Role = "access-logs"
  })
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket                  = aws_s3_bucket.data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_logging" "data" {
  bucket        = aws_s3_bucket.data.id
  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "s3-access/${aws_s3_bucket.data.id}/"
}

# Seed knowledge base into S3 so EC2 can sync at first boot
resource "aws_s3_object" "seed_docs" {
  for_each = fileset("${path.module}/../backend/source_data", "*.txt")

  bucket       = aws_s3_bucket.data.id
  key          = "source_data/${each.value}"
  source       = "${path.module}/../backend/source_data/${each.value}"
  etag         = filemd5("${path.module}/../backend/source_data/${each.value}")
  content_type = "text/plain"

  tags = local.common_tags
}

resource "aws_s3_object" "bootstrap_marker" {
  bucket       = aws_s3_bucket.data.id
  key          = "bootstrap/README.txt"
  content      = <<-EOT
    Pharmacy AI Assistant — S3 data bucket
    Seed docs live under source_data/
    EC2 user_data runs: aws s3 sync s3://BUCKET/source_data → app source_data
  EOT
  content_type = "text/plain"
  tags         = local.common_tags
}

# ---------------------------------------------------------------------------
# IAM — EC2 instance role can read/write app buckets
# ---------------------------------------------------------------------------

resource "aws_iam_role" "ec2" {
  name = "${local.name_prefix}-ec2-role-${random_id.suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "ec2_s3" {
  name = "${local.name_prefix}-ec2-s3"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ListBuckets"
        Effect = "Allow"
        Action = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = [
          aws_s3_bucket.data.arn,
          aws_s3_bucket.logs.arn,
        ]
      },
      {
        Sid    = "DataObjects"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = [
          "${aws_s3_bucket.data.arn}/*",
        ]
      },
      {
        Sid      = "WriteLogs"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject"]
        Resource = ["${aws_s3_bucket.logs.arn}/*"]
      },
    ]
  })
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${local.name_prefix}-ec2-profile-${random_id.suffix.hex}"
  role = aws_iam_role.ec2.name
  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Networking — security group
# ---------------------------------------------------------------------------

resource "aws_security_group" "pharmacy_ai" {
  name        = "${local.name_prefix}-sg-${random_id.suffix.hex}"
  description = "Pharmacy AI Assistant — SSH, HTTP UI, API"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  ingress {
    description = "Frontend (nginx)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Frontend Vite/mapped 3000"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Backend API"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-sg"
  })
}

# ---------------------------------------------------------------------------
# EC2 — Docker stack; user_data syncs knowledge base from S3 then starts app
# ---------------------------------------------------------------------------

resource "aws_instance" "app" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.pharmacy_ai.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name
  key_name               = var.key_name != "" ? var.key_name : null

  root_block_device {
    volume_size = var.root_volume_gb
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh.tpl", {
    aws_region     = var.aws_region
    data_bucket    = aws_s3_bucket.data.id
    logs_bucket    = aws_s3_bucket.logs.id
    project_name   = var.project_name
    git_repo_url   = var.git_repo_url
    git_branch     = var.git_branch
    ollama_model   = var.ollama_model
    ollama_embed   = var.ollama_embed_model
  }))

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ec2"
  })

  depends_on = [
    aws_s3_object.seed_docs,
    aws_iam_role_policy.ec2_s3,
  ]
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------

output "instance_id" {
  value = aws_instance.app.id
}

output "instance_public_ip" {
  value = aws_instance.app.public_ip
}

output "instance_public_dns" {
  value = aws_instance.app.public_dns
}

output "security_group_id" {
  value = aws_security_group.pharmacy_ai.id
}

output "s3_data_bucket" {
  description = "Primary app data bucket (seed docs under source_data/)"
  value       = aws_s3_bucket.data.id
}

output "s3_logs_bucket" {
  description = "S3 access logs + optional app logs"
  value       = aws_s3_bucket.logs.id
}

output "aws_profile_used" {
  description = "Named profile passed into the AWS provider (empty = default credential chain)"
  value       = var.aws_profile
}

output "frontend_url" {
  value = "http://${aws_instance.app.public_ip}:3000"
}

output "backend_url" {
  value = "http://${aws_instance.app.public_ip}:8000"
}

output "health_url" {
  value = "http://${aws_instance.app.public_ip}:8000/api/health"
}

output "ssh_hint" {
  value = var.key_name != "" ? "ssh -i <key.pem> ubuntu@${aws_instance.app.public_ip}" : "Set key_name to enable SSH"
}
