variable "name" {
  description = "Name prefix, e.g. acme-prod"
  type        = string
}

variable "alb_arn" {
  description = "ARN of the ALB this Web ACL protects"
  type        = string
}

variable "host_rules" {
  description = <<-EOT
    Per-hostname WAF configuration. One Web ACL covers the whole ALB, so hostnames are
    separated by scope-down statements on the Host header rather than by separate ACLs.

      rate_limit          requests per 5 minutes per IP, or null for no rate limiting
      managed_rule_groups AWS managed rule group names, e.g. AWSManagedRulesCommonRuleSet
      count_only          true logs what would be blocked without blocking it. Start here.
      login_rate_limit    a tighter per-IP limit applied only to login_path_prefixes
      login_path_prefixes URI path prefixes treated as authentication, e.g. ["/login"]
  EOT
  type = map(object({
    rate_limit          = optional(number)
    managed_rule_groups = optional(list(string), [])
    count_only          = optional(bool, true)

    # A much lower limit applied only to the authentication paths, so a credential
    # stuffing run trips it long before a busy clinic trips the blanket limit.
    login_rate_limit    = optional(number)
    login_path_prefixes = optional(list(string), [])
  }))
}

variable "enable_logging" {
  description = "Send WAF decisions to CloudWatch. Required to tune rules while in count mode."
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "WAF log retention"
  type        = number
  default     = 30
}
