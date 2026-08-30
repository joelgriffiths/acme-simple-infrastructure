output "role_name" {
  description = "Role name to paste into the Datadog AWS integration configuration"
  value       = aws_iam_role.datadog.name
}

output "role_arn" {
  description = "Role ARN"
  value       = aws_iam_role.datadog.arn
}
