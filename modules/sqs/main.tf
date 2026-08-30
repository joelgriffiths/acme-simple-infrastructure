# One reminder-dispatch queue with a dead-letter queue. The worker pulls jobs and calls
# the third-party SMS/email provider; SQS gives durable retries and a DLQ for sends that
# keep failing, which is exactly the failure mode of an external dependency.
resource "aws_sqs_queue" "dlq" {
  name                      = "${var.name}-dlq"
  message_retention_seconds = var.dlq_retention_seconds
  sqs_managed_sse_enabled   = true
  tags                      = { Name = "${var.name}-dlq" }
}

resource "aws_sqs_queue" "this" {
  name                       = var.name
  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.message_retention_seconds
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = { Name = var.name }
}
