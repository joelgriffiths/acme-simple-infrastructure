variable "name" {
  description = "ECS cluster name (e.g. acme-staging)"
  type        = string
}

variable "container_insights" {
  description = "Enable CloudWatch Container Insights"
  type        = bool
  default     = true
}
