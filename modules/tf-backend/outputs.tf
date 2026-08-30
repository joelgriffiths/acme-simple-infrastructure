output "state_bucket" {
  description = "State bucket name"
  value       = aws_s3_bucket.state.id
}

output "lock_table" {
  description = "Lock table name"
  value       = aws_dynamodb_table.locks.name
}
