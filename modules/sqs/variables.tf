variable "name" {
  description = "Queue name (e.g. acme-staging-reminders)"
  type        = string
}

variable "visibility_timeout_seconds" {
  description = "Visibility timeout (>= worker max processing time)"
  type        = number
  default     = 60
}

variable "message_retention_seconds" {
  description = "How long messages live in the main queue (default 4 days)"
  type        = number
  default     = 345600
}

variable "dlq_retention_seconds" {
  description = "DLQ retention (default 14 days for investigation)"
  type        = number
  default     = 1209600
}

variable "max_receive_count" {
  description = "Receives before a message is routed to the DLQ"
  type        = number
  default     = 5
}
