# One customer-managed KMS key per environment, used for two things:
#   1. SOPS encrypts envs/<env>/secrets/*.enc.yaml against it.
#   2. SSM SecureString parameters in that environment are encrypted with it.
#
# The key is deliberately per-environment. A staging credential leak must not give anyone
# the ability to decrypt a prod secret, and when prod moves to its own AWS account the key
# moves with it and nothing else changes.

data "aws_caller_identity" "current" {}

resource "aws_kms_key" "this" {
  description             = "Environment data key for ${var.environment}: SOPS files, SSM SecureString parameters, ECR image layers"
  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.key.json

  tags = { Name = "${var.name_prefix}-secrets", Environment = var.environment }
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.name_prefix}-secrets"
  target_key_id = aws_kms_key.this.key_id
}

data "aws_iam_policy_document" "key" {
  # Account root keeps administrative control so the key can never be orphaned.
  statement {
    sid       = "AccountAdmin"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  # Humans and CI that encrypt/decrypt SOPS files for this environment.
  dynamic "statement" {
    for_each = length(var.secret_writer_arns) > 0 ? [1] : []
    content {
      sid    = "SopsEncryptDecrypt"
      effect = "Allow"
      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey",
      ]
      resources = ["*"]
      principals {
        type        = "AWS"
        identifiers = var.secret_writer_arns
      }
    }
  }

  # Workloads that only read: ECS execution roles resolving SecureString parameters.
  dynamic "statement" {
    for_each = length(var.secret_reader_arns) > 0 ? [1] : []
    content {
      sid       = "WorkloadDecrypt"
      effect    = "Allow"
      actions   = ["kms:Decrypt", "kms:DescribeKey"]
      resources = ["*"]
      principals {
        type        = "AWS"
        identifiers = var.secret_reader_arns
      }
    }
  }
}
