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

# Profile: TF_VAR_aws_profile / -var / detect script / default credential chain
provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile != "" ? var.aws_profile : null
}

data "aws_caller_identity" "current" {}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

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
  # ALB needs >= 2 subnets in different AZs
  alb_subnet_ids = slice(data.aws_subnets.default.ids, 0, min(2, length(data.aws_subnets.default.ids)))
}

# ---------------------------------------------------------------------------
# S3 - seed knowledge + logs (via modules/s3_bucket)
# ---------------------------------------------------------------------------

module "data_bucket" {
  source            = "./modules/s3_bucket"
  bucket_name       = local.bucket_data
  force_destroy     = var.force_destroy_buckets
  enable_versioning = true
  tags              = merge(local.common_tags, { Name = "${local.name_prefix}-data", Role = "app-data" })
}

module "logs_bucket" {
  source        = "./modules/s3_bucket"
  bucket_name   = local.bucket_logs
  force_destroy = var.force_destroy_buckets
  tags          = merge(local.common_tags, { Name = "${local.name_prefix}-logs", Role = "access-logs" })
}

resource "aws_s3_bucket_logging" "data" {
  bucket        = module.data_bucket.id
  target_bucket = module.logs_bucket.id
  target_prefix = "s3-access/${module.data_bucket.id}/"
}

resource "aws_s3_object" "seed_docs" {
  for_each = fileset("${path.module}/../backend/source_data", "*.txt")

  bucket       = module.data_bucket.id
  key          = "source_data/${each.value}"
  source       = "${path.module}/../backend/source_data/${each.value}"
  etag         = filemd5("${path.module}/../backend/source_data/${each.value}")
  content_type = "text/plain"
  tags         = local.common_tags
}

resource "aws_s3_object" "bootstrap_marker" {
  bucket       = module.data_bucket.id
  key          = "bootstrap/README.txt"
  content      = <<-EOT
    Pharmacy AI Assistant seed data bucket.
    Objects under source_data/ are synced at EC2 user_data boot.
  EOT
  content_type = "text/plain"
  tags         = local.common_tags
}
