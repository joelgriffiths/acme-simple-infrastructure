output "bucket_name" {
  description = "Bucket name, passed to the ALB's access_logs block"
  value       = aws_s3_bucket.logs.id
}

output "bucket_arn" {
  description = "Bucket ARN"
  value       = aws_s3_bucket.logs.arn
}

output "log_prefixes" {
  description = "Key prefixes written under, one per load balancer"
  value       = var.log_prefixes
}
