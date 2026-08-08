variable "aws_region" {
  type        = string
  description = "AWS region for resources"
  default     = "us-east-1"
}

variable "aws_profile" {
  type        = string
  description = "Named AWS shared config/credentials profile (e.g. brian or default). Leave empty to use the default AWS credential chain. Prefer scripts/detect_aws_profile.py when running locally."
  default     = ""
}

variable "project_name" {
  type    = string
  default = "pharmacy-ai-assistant"
}

variable "instance_type" {
  type    = string
  default = "t3.medium"
}

variable "ami_id" {
  type        = string
  description = "AMI ID for the region (update per region)"
  default     = "ami-0c7217cdde317cfec"
}

variable "key_name" {
  type        = string
  description = "Optional EC2 key pair name"
  default     = ""
}

variable "allowed_ssh_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to SSH (tighten in real use)"
  default     = ["0.0.0.0/0"]
}
