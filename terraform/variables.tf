variable "aws_region" {
  type        = string
  description = "AWS region for resources"
  default     = "us-east-1"
}

variable "aws_profile" {
  type        = string
  description = "Named AWS shared profile (brian or default). Empty = default credential chain. Prefer scripts/detect_aws_profile.py."
  default     = ""
}

variable "project_name" {
  type    = string
  default = "pharmacy-ai-assistant"
}

variable "environment" {
  type    = string
  default = "demo"
}

variable "instance_type" {
  type        = string
  description = "EC2 size — t3.medium recommended for Ollama; use t3.large if answers are slow"
  default     = "t3.medium"
}

variable "ami_id" {
  type        = string
  description = "Ubuntu 22.04 AMI for the region (update if invalid in your account/region)"
  # Ubuntu 22.04 LTS amd64 — us-east-1 (verify with: aws ec2 describe-images)
  default = "ami-0c7217cdde317cfec"
}

variable "key_name" {
  type        = string
  description = "EC2 key pair name in this region (required for SSH). Create in AWS console if needed."
  default     = ""
}

variable "allowed_ssh_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to SSH — tighten to your IP/32 for real demos"
  default     = ["0.0.0.0/0"]
}

variable "root_volume_gb" {
  type        = number
  description = "Root volume size (models + Docker images need space)"
  default     = 40
}

variable "force_destroy_buckets" {
  type        = bool
  description = "Allow terraform destroy to empty and delete S3 buckets"
  default     = true
}

variable "git_repo_url" {
  type        = string
  description = "Git repo cloned onto EC2 at boot"
  default     = "https://github.com/bjslusher/pharmacy-ai-assistant.git"
}

variable "git_branch" {
  type    = string
  default = "main"
}

variable "ollama_model" {
  type    = string
  default = "llama3"
}

variable "ollama_embed_model" {
  type    = string
  default = "nomic-embed-text"
}
