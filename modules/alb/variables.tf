variable "name" {
  description = "Name prefix (e.g. acme-staging)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "Subnets for the ALB: public for an internet-facing one, private for an internal one"
  type        = list(string)
}

variable "certificate_arn" {
  description = "ACM certificate ARN for the HTTPS listener"
  type        = string
}

variable "ingress_cidrs" {
  description = "CIDRs allowed to reach the ALB. Public app -> 0.0.0.0/0; lock down in staging."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "internal" {
  description = "Internal ALB (no public IP). Default false (patient/clinic facing)."
  type        = bool
  default     = false
}

variable "enable_deletion_protection" {
  description = "Protect the ALB from accidental deletion (enable in prod)"
  type        = bool
  default     = false
}

variable "access_logs_bucket" {
  description = "S3 bucket for access logs (from modules/alb-access-logs). Null disables access logging."
  type        = string
  default     = null
}

variable "access_logs_prefix" {
  description = "Key prefix within the access log bucket"
  type        = string
  default     = "alb"
}
