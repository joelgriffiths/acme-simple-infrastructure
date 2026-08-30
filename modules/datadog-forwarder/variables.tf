variable "name" {
  description = "Name prefix, e.g. acme-prod"
  type        = string
}

variable "datadog_site" {
  description = "Datadog site, e.g. datadoghq.com"
  type        = string
  default     = "datadoghq.com"
}

variable "kms_key_id" {
  description = "KMS key encrypting the forwarder's API key secret (the environment's key)"
  type        = string
}

variable "template_url" {
  description = "Datadog Forwarder CloudFormation template. Pin a version rather than latest once in production."
  type        = string
  default     = "https://datadog-cloudformation-template.s3.amazonaws.com/aws/forwarder/latest.yaml"
}

variable "extra_parameters" {
  description = "Additional CloudFormation parameters, e.g. DdTags or DdFetchLambdaTags"
  type        = map(string)
  default     = {}
}
