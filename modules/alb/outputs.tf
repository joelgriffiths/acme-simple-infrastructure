output "alb_arn" {
  description = "ALB ARN"
  value       = aws_lb.this.arn
}

output "alb_dns_name" {
  description = "ALB DNS name (point Route53 records here)"
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "ALB hosted zone ID (for Route53 alias records)"
  value       = aws_lb.this.zone_id
}

output "https_listener_arn" {
  description = "HTTPS listener ARN (services attach host rules here)"
  value       = aws_lb_listener.https.arn
}

output "security_group_id" {
  description = "ALB security group ID (allow this on task SGs)"
  value       = aws_security_group.alb.id
}

output "arn_suffix" {
  description = "ALB ARN suffix (app/<name>/<id>). This is the loadbalancer tag value in CloudWatch and Datadog."
  value       = aws_lb.this.arn_suffix
}
