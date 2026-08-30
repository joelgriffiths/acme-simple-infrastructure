variable "env" {
  description = "Environment name, used in monitor titles and the env: tag (staging, prod)"
  type        = string
}

variable "project" {
  description = "Project tag value"
  type        = string
  default     = "acme"
}

variable "extra_tags" {
  description = "Additional Datadog tags applied to every monitor"
  type        = list(string)
  default     = []
}

# --- Notification routing ---
variable "page_target" {
  description = "Datadog handle that wakes someone up, e.g. @pagerduty-acme-primary. In staging this should be a Slack channel."
  type        = string
}

variable "notify_target" {
  description = "Datadog handle for non-urgent alerts, e.g. @slack-acme-eng"
  type        = string
}

# --- Resource identifiers the monitors query against ---
variable "load_balancer_name" {
  description = "Internet-facing ALB name as it appears in the aws.applicationelb loadbalancer tag"
  type        = string
}

variable "internal_load_balancer_name" {
  description = "Internal ALB name (aws.applicationelb loadbalancer tag). Watched only for having no healthy targets."
  type        = string
}

variable "db_instance_identifier" {
  description = "RDS instance identifier"
  type        = string
}

variable "queues" {
  description = <<-EOT
    Async queues to monitor. Each gets a dead-letter alarm and a backlog-age alarm.

      label            human name used in the alert title and body
      queue_name       main queue name (the queuename dimension in CloudWatch)
      dlq_name         dead-letter queue name
      max_age_seconds  how stale the oldest message may get before it pages
  EOT
  type = map(object({
    label           = string
    queue_name      = string
    dlq_name        = string
    max_age_seconds = number
  }))
}

variable "worker_service_name" {
  description = "ECS service name for the reminder worker"
  type        = string
}

# --- Thresholds ---
variable "api_error_rate_threshold" {
  description = "Fraction of requests returning 5xx that constitutes an outage (0.02 = 2%)"
  type        = number
  default     = 0.02
}

variable "api_p95_latency_seconds" {
  description = "p95 target response time considered degraded"
  type        = number
  default     = 1.0
}

variable "rds_free_storage_threshold_gb" {
  description = "Page when free database storage drops below this many GB"
  type        = number
  default     = 5
}

variable "rds_cpu_threshold" {
  description = "Database CPU percentage considered high"
  type        = number
  default     = 80
}

variable "rds_connection_threshold" {
  description = "Connection count that signals the need for a pooler. Set below the instance limit."
  type        = number
  default     = 80
}

# --- Behaviour ---
variable "notify_no_data" {
  description = "Alert when a monitor stops receiving data. On in prod: silence usually means the integration broke."
  type        = bool
  default     = true
}

variable "no_data_timeframe_minutes" {
  description = "Minutes without data before a no-data alert fires"
  type        = number
  default     = 30
}

variable "renotify_interval_minutes" {
  description = "Re-page interval for unacknowledged priority-1 monitors"
  type        = number
  default     = 30
}

variable "permanent_downtime" {
  description = "Mute every monitor in this environment permanently. True in staging: we want the data and the dashboards, never the page."
  type        = bool
  default     = false
}

# --- SLO ---
variable "create_slo" {
  description = "Create the booking API availability SLO. Prod only; an SLO on staging is meaningless."
  type        = bool
  default     = false
}

variable "slo_target" {
  description = "SLO target percentage over 30 days"
  type        = number
  default     = 99.9
}

variable "slo_warning" {
  description = "SLO warning percentage; crossing it means the error budget is burning fast"
  type        = number
  default     = 99.95
}
