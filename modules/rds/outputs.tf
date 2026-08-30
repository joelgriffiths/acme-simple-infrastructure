output "endpoint" {
  description = "DB endpoint (host:port)"
  value       = aws_db_instance.this.endpoint
}

output "address" {
  description = "DB hostname"
  value       = aws_db_instance.this.address
}

output "port" {
  description = "DB port"
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "Initial database name"
  value       = aws_db_instance.this.db_name
}

output "master_user_secret_arn" {
  description = "Secrets Manager ARN of the RDS-managed master credentials"
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "security_group_id" {
  description = "DB security group ID"
  value       = aws_security_group.db.id
}

output "identifier" {
  description = "DB instance identifier (the dbinstanceidentifier dimension in CloudWatch)"
  value       = aws_db_instance.this.identifier
}
