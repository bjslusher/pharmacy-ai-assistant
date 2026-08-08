terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Profile is resolved on the machine that runs Terraform:
#   1) TF_VAR_aws_profile / -var aws_profile=...
#   2) scripts/detect_aws_profile.py  (prefers brian, then default)
#   3) empty → AWS SDK default chain (env keys, instance role, etc.)
provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile != "" ? var.aws_profile : null
}

resource "aws_security_group" "pharmacy_ai" {
  name        = "${var.project_name}-sg"
  description = "Pharmacy AI Assistant security group"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
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

  tags = {
    Name    = "${var.project_name}-sg"
    Project = var.project_name
  }
}

resource "aws_instance" "app" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.pharmacy_ai.id]
  key_name               = var.key_name != "" ? var.key_name : null

  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y || yum update -y
              # Placeholder: install Docker and bootstrap the pharmacy-ai stack
              EOF

  tags = {
    Name    = "${var.project_name}-ec2"
    Project = var.project_name
  }
}

output "instance_public_ip" {
  value = aws_instance.app.public_ip
}

output "security_group_id" {
  value = aws_security_group.pharmacy_ai.id
}

output "aws_profile_used" {
  description = "Named profile passed into the AWS provider (empty = default credential chain)"
  value       = var.aws_profile
}
