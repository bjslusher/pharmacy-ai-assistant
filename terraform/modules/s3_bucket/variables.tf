variable "bucket_name" {
  type        = string
  description = "Globally unique S3 bucket name"
}

variable "force_destroy" {
  type        = bool
  description = "Allow terraform destroy to empty the bucket"
  default     = true
}

variable "enable_versioning" {
  type        = bool
  description = "Enable S3 versioning"
  default     = false
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to the bucket"
  default     = {}
}
