# S3 bucket for ALB access logs, plus the wiring that ships them on to Datadog.
#
# ALB access logs can only be delivered to S3, so the path to Datadog is S3 -> Lambda
# (the Datadog Forwarder) -> Datadog. The bucket is the durable audit trail and Datadog is
# the search interface; keeping both matters because the audit trail should outlive the
# monitoring vendor contract.
#
# ONE CONSTRAINT WORTH KNOWING: ALB access logs support SSE-S3 only. Pointing this bucket
# at a KMS CMK silently breaks log delivery, which is why this is the one store in the repo
# not using the environment's KMS key.

data "aws_caller_identity" "current" {}
data "aws_elb_service_account" "current" {}

locals {
  # One bucket serves both load balancers, each writing under its own prefix, so the
  # delivery grant is scoped to exactly those paths rather than the whole bucket.
  delivery_paths = [
    for p in var.log_prefixes :
    "${aws_s3_bucket.logs.arn}/${p}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
  ]
}

resource "aws_s3_bucket" "logs" {
  bucket        = var.bucket_name
  force_destroy = var.force_destroy
  tags          = { Name = var.bucket_name, Purpose = "alb-access-logs" }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id
  versioning_configuration { status = "Enabled" }
}

# Access logs are an audit record with a defined life, not something to keep forever.
resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "expire-access-logs"
    status = "Enabled"
    filter {}

    expiration {
      days = var.retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Two delivery principals: older regions (us-west-2 included) write as a regional ELB
# account, newer ones use the log delivery service principal. Both are granted so this
# module works wherever it is applied.
data "aws_iam_policy_document" "logs" {
  statement {
    sid     = "AllowElbAccountWrite"
    effect  = "Allow"
    actions = ["s3:PutObject"]
    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.current.arn]
    }
    resources = local.delivery_paths
  }

  statement {
    sid     = "AllowLogDeliveryServiceWrite"
    effect  = "Allow"
    actions = ["s3:PutObject"]
    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }
    resources = local.delivery_paths
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }

  statement {
    sid     = "AllowLogDeliveryAclCheck"
    effect  = "Allow"
    actions = ["s3:GetBucketAcl"]
    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }
    resources = [aws_s3_bucket.logs.arn]
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.logs.arn, "${aws_s3_bucket.logs.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = data.aws_iam_policy_document.logs.json
}

# --- Ship each new log file to Datadog ---
resource "aws_lambda_permission" "forwarder" {
  count          = var.forwarder_lambda_arn == null ? 0 : 1
  statement_id   = "AllowExecutionFromAlbLogBucket"
  action         = "lambda:InvokeFunction"
  function_name  = var.forwarder_lambda_arn
  principal      = "s3.amazonaws.com"
  source_arn     = aws_s3_bucket.logs.arn
  source_account = data.aws_caller_identity.current.account_id
}

resource "aws_s3_bucket_notification" "forwarder" {
  count  = var.forwarder_lambda_arn == null ? 0 : 1
  bucket = aws_s3_bucket.logs.id

  dynamic "lambda_function" {
    for_each = toset(var.log_prefixes)
    content {
      lambda_function_arn = var.forwarder_lambda_arn
      events              = ["s3:ObjectCreated:*"]
      filter_prefix       = "${lambda_function.value}/"
    }
  }

  depends_on = [aws_lambda_permission.forwarder]
}
