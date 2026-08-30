output "queue_url" { value = aws_sqs_queue.this.url }
output "queue_arn" { value = aws_sqs_queue.this.arn }
output "dlq_arn" { value = aws_sqs_queue.dlq.arn }

output "queue_name" {
  description = "Main queue name (the queuename dimension in CloudWatch)"
  value       = aws_sqs_queue.this.name
}

output "dlq_name" {
  description = "Dead-letter queue name"
  value       = aws_sqs_queue.dlq.name
}
