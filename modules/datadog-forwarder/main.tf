# The Datadog Forwarder: a Lambda that reads log files from S3 and ships them to Datadog.
#
# Deployed from Datadog's own CloudFormation template rather than hand-written Terraform.
# The forwarder is a moving target that Datadog maintains, and reimplementing its IAM,
# layers, and runtime here would mean owning their upgrade path forever. `terraform apply`
# still owns the stack, so it is not a click-ops resource.
#
# THE ONE EXCEPTION TO THE SECRETS SPLIT: everything else in this repo keeps application
# secrets in SSM. The forwarder template reads its API key from Secrets Manager and offers
# no SSM option, so this module creates its own Secrets Manager container. Container only,
# as everywhere else: the value is written out of band by scripts/secrets-push.sh.

resource "aws_secretsmanager_secret" "api_key" {
  name        = "${var.name}/datadog-forwarder-api-key"
  description = "Datadog API key for the log forwarder Lambda. Value set out of band from SOPS."
  kms_key_id  = var.kms_key_id

  tags = { Name = "${var.name}/datadog-forwarder-api-key" }
}

resource "aws_secretsmanager_secret_version" "api_key" {
  secret_id     = aws_secretsmanager_secret.api_key.id
  secret_string = "PLACEHOLDER-set-out-of-band"

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_cloudformation_stack" "forwarder" {
  name         = "${var.name}-datadog-forwarder"
  template_url = var.template_url

  capabilities = [
    "CAPABILITY_IAM",
    "CAPABILITY_NAMED_IAM",
    "CAPABILITY_AUTO_EXPAND",
  ]

  parameters = merge({
    DdApiKeySecretArn = aws_secretsmanager_secret.api_key.arn
    DdSite            = var.datadog_site
    FunctionName      = "${var.name}-datadog-forwarder"
  }, var.extra_parameters)

  tags = { Name = "${var.name}-datadog-forwarder" }

  depends_on = [aws_secretsmanager_secret_version.api_key]
}
