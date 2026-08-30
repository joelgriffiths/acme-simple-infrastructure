variable "name_prefix" {
  description = "Name prefix, e.g. acme-staging"
  type        = string
}

variable "external_id" {
  description = "External ID issued by Datadog when the AWS integration is created. Required: without it any Datadog customer could assume this role."
  type        = string
}

variable "datadog_aws_account_id" {
  description = "Datadog's AWS account ID for the commercial regions"
  type        = string
  default     = "464622532012"
}
