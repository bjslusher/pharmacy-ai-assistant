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
# S3 — seed knowledge + logs
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "data" {
  bucket        = local.bucket_data
  force_destroy = var.force_destroy_buckets
  tags = merge(local.common_tags, { Name = "${local.name_prefix}-data", Role = "app-data" })
}

resource "aws_s3_bucket" "logs" {
  bucket        = local.bucket_logs
  force_destroy = var.force_destroy_buckets
  tags = merge(local.common_tags, { Name = "${local.name_prefix}-logs", Role = "access-logs" })
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
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_logging" "data" {
  bucket        = aws_s3_bucket.data.id
  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "s3-access/${aws_s3_bucket.data.id}/"
}

resource "aws_s3_object" "seed_docs" {
  for_each = fileset("${path.module}/../backend/source_data", "*.txt")

  bucket       = aws_s3_bucket.data.id
  key          = "source_data/${each.value}"
  source       = "${path.module}/../backend/source_data/${each.value}"
  etag         = filemd5("${path.module}/../backend/source_data/${each.value}")
  content_type = "text/plain"
  tags         = local.common_tags
}

resource "aws_s3_object" "bootstrap_marker" {
  bucket       = aws_s3_bucket.data.id
  key          = "bootstrap/README.txt"
  content      = <<-EOT
    Pharmacy AI Assistant — S3 data bucket
    Seed docs under source_data/
    EC2/ASG user_data: aws s3 sync → app source_data, then docker compose
  EOT
  content_type = "text/plain"
  tags         = local.common_tags
}

# ---------------------------------------------------------------------------
# IAM — instance role for S3
# ---------------------------------------------------------------------------

resource "aws_iam_role" "ec2" {
  name = "${local.name_prefix}-ec2-role-${random_id.suffix.hex}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
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
        Sid      = "ListBuckets"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = [aws_s3_bucket.data.arn, aws_s3_bucket.logs.arn]
      },
      {
        Sid      = "DataObjects"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = ["${aws_s3_bucket.data.arn}/*"]
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
# Security groups — ALB + app instances
# ---------------------------------------------------------------------------

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg-${random_id.suffix.hex}"
  description = "ALB — public HTTP"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-alb-sg" })
}

resource "aws_security_group" "app" {
  name        = "${local.name_prefix}-app-sg-${random_id.suffix.hex}"
  description = "App instances — traffic from ALB + optional SSH"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "Frontend from ALB"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "Backend API from ALB"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Direct access for demo/debug (optional; ALB is the preferred path)
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  ingress {
    description = "Direct frontend (demo)"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Direct backend (demo)"
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

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-app-sg" })
}

# ---------------------------------------------------------------------------
# Launch template + Auto Scaling Group (demo scale 1–2)
# ---------------------------------------------------------------------------

resource "aws_launch_template" "app" {
  name_prefix   = "${local.name_prefix}-lt-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name != "" ? var.key_name : null

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }

  vpc_security_group_ids = [aws_security_group.app.id]

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size           = var.root_volume_gb
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh.tpl", {
    aws_region   = var.aws_region
    data_bucket  = aws_s3_bucket.data.id
    logs_bucket  = aws_s3_bucket.logs.id
    project_name = var.project_name
    git_repo_url = var.git_repo_url
    git_branch   = var.git_branch
    ollama_model = var.ollama_model
    ollama_embed = var.ollama_embed_model
  }))

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, { Name = "${local.name_prefix}-asg-instance" })
  }

  tags = local.common_tags

  depends_on = [
    aws_s3_object.seed_docs,
    aws_iam_role_policy.ec2_s3,
  ]
}

resource "aws_autoscaling_group" "app" {
  name                      = "${local.name_prefix}-asg-${random_id.suffix.hex}"
  vpc_zone_identifier       = data.aws_subnets.default.ids
  min_size                  = var.asg_min_size
  max_size                  = var.asg_max_size
  desired_capacity          = var.asg_desired_capacity
  health_check_type         = "ELB"
  health_check_grace_period = var.asg_health_check_grace_seconds
  target_group_arns = [
    aws_lb_target_group.frontend.arn,
    aws_lb_target_group.backend.arn,
  ]

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${local.name_prefix}-asg"
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = var.project_name
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Optional CPU scale-out policy (demo — shows ASG can react to load)
resource "aws_autoscaling_policy" "cpu_target" {
  name                   = "${local.name_prefix}-cpu-target"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = var.asg_cpu_target
  }
}

# ---------------------------------------------------------------------------
# Application Load Balancer — path routing /api* → backend, else → frontend
# ---------------------------------------------------------------------------

resource "aws_lb" "app" {
  name               = "${substr(local.name_prefix, 0, 12)}-${random_id.suffix.hex}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = local.alb_subnet_ids

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-alb" })
}

resource "aws_lb_target_group" "frontend" {
  name     = "${substr(local.name_prefix, 0, 10)}-fe-${random_id.suffix.hex}"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    enabled             = true
    path                = "/"
    port                = "3000"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 5
    interval            = 30
    matcher             = "200-399"
  }

  tags = local.common_tags
}

resource "aws_lb_target_group" "backend" {
  name     = "${substr(local.name_prefix, 0, 10)}-be-${random_id.suffix.hex}"
  port     = 8000
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    enabled             = true
    path                = "/api/health"
    port                = "8000"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 10
    interval            = 30
    matcher             = "200"
  }

  tags = local.common_tags
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

resource "aws_lb_listener_rule" "api" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  condition {
    path_pattern {
      values = ["/api/*", "/docs", "/openapi.json", "/redoc"]
    }
  }
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------

output "alb_dns_name" {
  description = "Application Load Balancer DNS — preferred public entrypoint"
  value       = aws_lb.app.dns_name
}

output "frontend_url" {
  description = "UI via ALB (port 80)"
  value       = "http://${aws_lb.app.dns_name}"
}

output "backend_url" {
  description = "API via ALB path /api"
  value       = "http://${aws_lb.app.dns_name}"
}

output "health_url" {
  value = "http://${aws_lb.app.dns_name}/api/health"
}

output "asg_name" {
  value = aws_autoscaling_group.app.name
}

output "asg_desired_capacity" {
  value = aws_autoscaling_group.app.desired_capacity
}

output "launch_template_id" {
  value = aws_launch_template.app.id
}

output "s3_data_bucket" {
  value = aws_s3_bucket.data.id
}

output "s3_logs_bucket" {
  value = aws_s3_bucket.logs.id
}

output "aws_profile_used" {
  value = var.aws_profile
}

output "security_group_app_id" {
  value = aws_security_group.app.id
}

output "security_group_alb_id" {
  value = aws_security_group.alb.id
}

output "ssh_hint" {
  value = var.key_name != "" ? "Find instance IPs in ASG/EC2 console, then: ssh -i <key.pem> ubuntu@<ip>" : "Set key_name to enable SSH"
}
