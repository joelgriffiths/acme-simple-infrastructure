variable "bucket_name" {
  description = "Globally unique bucket name, e.g. acme-prod-alb-logs-<account>"
  type        = string
}

variable "log_prefixes" {
  description = "Key prefixes written under, one per load balancer sharing this bucket"
  type        = list(string)
  default     = ["alb-public", "alb-internal"]
}

variable "retention_days" {
  description = "How long access logs are kept. This is a data-retention decision, not a cost one."
  type        = number
  default     = 365
}

variable "forwarder_lambda_arn" {
  description = "Datadog Forwarder Lambda ARN. Null keeps logs in S3 only."
  type        = string
  default     = null
}

variable "force_destroy" {
  description = "Allow destroying the bucket with logs still in it (staging only)"
  type        = bool
  default     = false
}
