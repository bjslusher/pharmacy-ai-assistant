# Terraform modules

| Module | Purpose |
|--------|---------|
| `s3_bucket` | Private encrypted S3 bucket + public access block (data & logs) |

Root `main.tf` composes these modules with ALB/ASG/IAM still in the root module for a readable single-env demo.
