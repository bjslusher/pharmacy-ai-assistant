# Primary outputs are also declared in main.tf.
# This summary map is handy for: terraform output -json summary

output "summary" {
  description = "Demo endpoints and core resource ids"
  value = {
    alb_dns     = aws_lb.app.dns_name
    frontend    = "http://${aws_lb.app.dns_name}"
    health      = "http://${aws_lb.app.dns_name}/api/health"
    asg_name    = aws_autoscaling_group.app.name
    data_bucket = module.data_bucket.id
    logs_bucket = module.logs_bucket.id
  }
}
