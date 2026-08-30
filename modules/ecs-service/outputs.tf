output "service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.this.name
}

output "task_security_group_id" {
  description = "Task SG ID (allow this on RDS / other backends)"
  value       = aws_security_group.task.id
}

output "task_role_arn" {
  description = "Task IAM role ARN"
  value       = aws_iam_role.task.arn
}

output "target_group_arn" {
  description = "Target group ARN (null for standalone services)"
  value       = var.attach_alb ? aws_lb_target_group.this[0].arn : null
}
