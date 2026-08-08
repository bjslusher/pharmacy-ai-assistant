# Convenience re-exports — primary outputs also live in main.tf
# Kept so `terraform output` documentation is easy to find.

output "summary" {
  value = {
    frontend   = "http://$${aws_instance.app.public_ip}:3000"
    backend    = "http://$${aws_instance.app.public_ip}:8000"
    health     = "http://$${aws_instance.app.public_ip}:8000/api/health"
    data_bucket = aws_s3_bucket.data.id
    logs_bucket = aws_s3_bucket.logs.id
  }
}
