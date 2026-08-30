# The AWS half of the Datadog integration: a role Datadog assumes to poll CloudWatch.
#
# This gets metrics for RDS, the ALB, SQS, and ECS with no agent and no application
# change, which is why it is worth doing first. The agent sidecars in modules/ecs-service
# add APM and custom metrics on top.
#
# Deliberately read-only, and deliberately not wildcarded to a whole service family: a
# monitoring vendor should never be able to change anything in the account or read object
# contents. The external ID is issued by Datadog when the integration is created in their
# UI or API; it is not a secret in the credential sense but it is what stops a confused
# deputy, so it is required rather than defaulted.

data "aws_iam_policy_document" "assume" {
  statement {
    sid     = "DatadogAssume"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.datadog_aws_account_id}:root"]
    }

    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.external_id]
    }
  }
}

resource "aws_iam_role" "datadog" {
  name                 = "${var.name_prefix}-datadog-integration"
  description          = "Read-only role Datadog assumes to poll CloudWatch metrics"
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  max_session_duration = 3600

  tags = { Name = "${var.name_prefix}-datadog-integration" }
}

data "aws_iam_policy_document" "read" {
  statement {
    sid    = "MetricsAndInventory"
    effect = "Allow"
    actions = [
      "cloudwatch:Describe*",
      "cloudwatch:Get*",
      "cloudwatch:List*",
      "ecs:Describe*",
      "ecs:List*",
      "elasticloadbalancing:Describe*",
      "rds:Describe*",
      "rds:List*",
      "sqs:GetQueueAttributes",
      "sqs:ListQueues",
      "tag:GetResources",
      "tag:GetTagKeys",
      "tag:GetTagValues",
    ]
    resources = ["*"]
  }

  # Health events (planned RDS maintenance, AZ impairment) show up as Datadog events.
  statement {
    sid    = "HealthEvents"
    effect = "Allow"
    actions = [
      "health:DescribeEvents",
      "health:DescribeEventDetails",
      "health:DescribeAffectedEntities",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "read" {
  name   = "datadog-read"
  role   = aws_iam_role.datadog.id
  policy = data.aws_iam_policy_document.read.json
}
