output "key_arn" {
  description = "KMS key ARN"
  value       = aws_kms_key.this.arn
}

output "key_id" {
  description = "KMS key ID"
  value       = aws_kms_key.this.key_id
}

output "alias_name" {
  description = "Alias, e.g. alias/acme-staging-secrets"
  value       = aws_kms_alias.this.name
}

output "alias_arn" {
  description = "Alias ARN. This is what goes in .sops.yaml."
  value       = aws_kms_alias.this.arn
}
