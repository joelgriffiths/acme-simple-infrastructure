output "repository_urls" {
  description = "Short service name => repository URL (registry host + repo path)"
  value       = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}

output "repository_arns" {
  description = "Short service name => repository ARN"
  value       = { for k, r in aws_ecr_repository.this : k => r.arn }
}
