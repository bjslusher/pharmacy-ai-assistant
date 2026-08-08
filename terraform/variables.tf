variable "aws_region" {
  type    = string
  default = "us-east-1"
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
  type    = string
  default = ""
}

variable "allowed_ssh_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}
