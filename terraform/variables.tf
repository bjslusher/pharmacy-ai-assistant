variable "aws_region" {
  type        = string
  description = "AWS region for resources (us-east-1 is common for free-tier AMIs)"
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
  type = string
  description = <<-EOT
    EC2 size. Default t3.micro is Free Tier eligible (750 hrs/mo for eligible accounts).
    Ollama will be slow/tight on memory — for smoother demos after free tier, use t3.small or t3.medium.
  EOT
  default = "t3.micro"
}

variable "ami_id" {
  type        = string
  description = "Ubuntu 22.04 AMI for the region (free-tier eligible Linux). Update if invalid in your account/region."
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
  type = number
  description = <<-EOT
    Root EBS gp3 size in GB. Default 30 matches Free Tier EBS allowance.
    Docker images + a small Ollama model fit; larger models may need 40+ (billable beyond free tier).
  EOT
  default = 30
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
  type = string
  description = <<-EOT
    Chat model pulled on the instance. Default llama3.2:1b is small enough for t3.micro Free Tier.
    For higher quality on larger instances: llama3 or llama3.2.
  EOT
  default = "llama3.2:1b"
}

variable "ollama_embed_model" {
  type        = string
  description = "Embedding model (nomic-embed-text is relatively small and works with Free Tier disk)"
  default     = "nomic-embed-text"
}
