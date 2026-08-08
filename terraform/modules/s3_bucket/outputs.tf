output "id" {
  description = "Bucket name / id"
  value       = aws_s3_bucket.this.id
}

output "arn" {
  description = "Bucket ARN"
  value       = aws_s3_bucket.this.arn
}

output "bucket_domain_name" {
  value = aws_s3_bucket.this.bucket_domain_name
}
