terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
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
