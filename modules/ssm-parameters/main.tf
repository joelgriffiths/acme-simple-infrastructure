# Application configuration and secrets in SSM Parameter Store.
#
# Two kinds of parameter, deliberately kept apart:
#
#   secret_parameters  SecureString, encrypted with the environment's KMS key. Terraform
#                      creates the CONTAINER with a placeholder and then ignores the value
#                      forever. Real values arrive out of band: CI decrypts
#                      envs/<env>/secrets/*.enc.yaml with SOPS and calls put-parameter.
#                      No secret value ever enters Terraform state or a plan diff.
#
#   config_parameters  Plain String. Values Terraform already knows because it built the
#                      thing they describe (database endpoint, queue URL). Nothing secret
#                      goes here.
#
# Database master credentials are NOT here. They stay RDS-managed in Secrets Manager so
# they keep native rotation and never exist in any file, encrypted or otherwise. See
# ARCHITECTURE.md for why the two are split.

resource "aws_ssm_parameter" "secret" {
  for_each = var.secret_parameters

  name        = "${var.prefix}/${each.key}"
  description = each.value
  type        = "SecureString"
  key_id      = var.kms_key_id
  value       = "PLACEHOLDER-set-out-of-band"
  tier        = "Standard"

  # The value is owned by the SOPS pipeline, not by Terraform.
  lifecycle {
    ignore_changes = [value]
  }

  tags = { Name = "${var.prefix}/${each.key}", Sensitivity = "secret" }
}

resource "aws_ssm_parameter" "config" {
  for_each = var.config_parameters

  name        = "${var.prefix}/${each.key}"
  description = "Managed by Terraform"
  type        = "String"
  value       = each.value
  tier        = "Standard"

  tags = { Name = "${var.prefix}/${each.key}", Sensitivity = "config" }
}
