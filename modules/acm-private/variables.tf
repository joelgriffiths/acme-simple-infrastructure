variable "name" {
  description = "Name prefix, e.g. acme-prod"
  type        = string
}

variable "ca_common_name" {
  description = "CA subject common name, e.g. Acme Internal Root CA"
  type        = string
}

variable "organization" {
  description = "CA subject organization"
  type        = string
  default     = "Acme Corp"
}

variable "organizational_unit" {
  description = "CA subject organizational unit"
  type        = string
  default     = "Infrastructure"
}

variable "country" {
  description = "CA subject country code"
  type        = string
  default     = "US"
}

variable "domain_name" {
  description = "Primary internal hostname for the leaf certificate"
  type        = string
}

variable "subject_alternative_names" {
  description = "Additional internal hostnames on the leaf certificate"
  type        = list(string)
  default     = []
}

variable "usage_mode" {
  description = <<-EOT
    GENERAL_PURPOSE issues certificates with normal lifetimes at roughly $400/month.
    SHORT_LIVED_CERTIFICATE caps certificates at 7 days for roughly $50/month, which only
    works if something renews them continuously. ACM does renew, but a weekly rotation on a
    load balancer certificate is a lot of moving parts to save $350; pick deliberately.
  EOT
  type        = string
  default     = "GENERAL_PURPOSE"

  validation {
    condition     = contains(["GENERAL_PURPOSE", "SHORT_LIVED_CERTIFICATE"], var.usage_mode)
    error_message = "usage_mode must be GENERAL_PURPOSE or SHORT_LIVED_CERTIFICATE."
  }
}

variable "key_algorithm" {
  description = "CA key algorithm"
  type        = string
  default     = "RSA_2048"
}

variable "signing_algorithm" {
  description = "CA signing algorithm"
  type        = string
  default     = "SHA256WITHRSA"
}

variable "ca_validity_years" {
  description = "Root CA certificate lifetime. Long, because rotating a root means redistributing it to every client."
  type        = number
  default     = 10
}

variable "deletion_window_in_days" {
  description = "Days a deleted CA stays restorable (7-30). Deleting a CA is not reversible after this."
  type        = number
  default     = 30
}
