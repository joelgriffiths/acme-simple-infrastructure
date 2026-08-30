output "lambda_arn" {
  description = "Forwarder Lambda ARN, for S3 bucket notifications"
  value       = aws_cloudformation_stack.forwarder.outputs["DatadogForwarderArn"]
}

output "api_key_secret_arn" {
  description = "Secrets Manager ARN holding the forwarder's Datadog API key"
  value       = aws_secretsmanager_secret.api_key.arn
}

output "api_key_secret_name" {
  description = "Secret name, for the out-of-band put-secret-value call"
  value       = aws_secretsmanager_secret.api_key.name
}
