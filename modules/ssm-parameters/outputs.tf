output "secret_arns" {
  description = "Short name => parameter ARN, for wiring into ECS task secrets"
  value       = { for k, p in aws_ssm_parameter.secret : k => p.arn }
}

output "secret_names" {
  description = "Short name => full parameter name, for the out-of-band put-parameter calls"
  value       = { for k, p in aws_ssm_parameter.secret : k => p.name }
}

output "config_arns" {
  description = "Short name => parameter ARN"
  value       = { for k, p in aws_ssm_parameter.config : k => p.arn }
}
