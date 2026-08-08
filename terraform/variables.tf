variable "aws_region" {
  type        = string
  description = "AWS region (us-east-1 common for free-tier AMIs)"
  default     = "us-east-1"
}

variable "aws_profile" {
  type        = string
  description = "Named AWS shared profile (brian or default). Empty = default credential chain."
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
  description = "EC2 size in the ASG. Default t3.micro is Free Tier eligible for compute hours."
  default     = "t3.micro"
}

variable "ami_id" {
  type        = string
  description = "Ubuntu 22.04 AMI for the region"
  default     = "ami-0c7217cdde317cfec"
}

variable "key_name" {
  type        = string
  description = "EC2 key pair name (SSH). Optional."
  default     = ""
}

variable "allowed_ssh_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to SSH — tighten to your IP/32 for real demos"
  default     = ["0.0.0.0/0"]
}

variable "root_volume_gb" {
  type        = number
  description = "Root EBS gp3 size (GB). Default 30 matches typical Free Tier EBS."
  default     = 30
}

variable "force_destroy_buckets" {
  type        = bool
  description = "Allow terraform destroy to empty and delete S3 buckets"
  default     = true
}

variable "git_repo_url" {
  type        = string
  description = "Git repo cloned onto instances at boot"
  default     = "https://github.com/bjslusher/pharmacy-ai-assistant.git"
}

variable "git_branch" {
  type    = string
  default = "main"
}

variable "ollama_model" {
  type        = string
  description = "Chat model on instances. Default small for t3.micro."
  default     = "llama3.2:1b"
}

variable "ollama_embed_model" {
  type    = string
  default = "nomic-embed-text"
}

# --- Auto Scaling (instructor demo) ---

variable "asg_min_size" {
  type        = number
  description = "ASG minimum instances"
  default     = 1
}

variable "asg_max_size" {
  type        = number
  description = "ASG maximum instances (demo ceiling)"
  default     = 2
}

variable "asg_desired_capacity" {
  type        = number
  description = "ASG desired capacity at apply"
  default     = 1
}

variable "asg_health_check_grace_seconds" {
  type        = number
  description = "Time for user_data/Docker/Ollama before ELB marks unhealthy"
  default     = 1200
}

variable "asg_cpu_target" {
  type        = number
  description = "Target tracking CPU %% for scale-out demo policy"
  default     = 60
}
