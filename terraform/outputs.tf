# Primary outputs are declared in main.tf.
# This file keeps a single summary map for quick terraform output -json use.

output "summary" {
  description = "Demo endpoints and core resource ids"
  value = {
    alb_dns     = aws_lb.app.dns_name
    frontend    = "http://${aws_lb.app.dns_name}"
    health      = "http://${aws_lb.app.dns_name}/api/health"
    asg_name    = aws_autoscaling_group.app.name
    data_bucket = aws_s3_bucket.data.id
    logs_bucket = aws_s3_bucket.logs.id
  }
}
