variable "name_prefix" {
  description = "Key/alias name prefix, e.g. acme-staging"
  type        = string
}

variable "environment" {
  description = "Environment this key belongs to (staging, prod). One key per environment."
  type        = string
}

variable "secret_writer_arns" {
  description = "IAM principals allowed to encrypt and decrypt (engineers, CI). Empty means account-root only."
  type        = list(string)
  default     = []
}

variable "secret_reader_arns" {
  description = "IAM principals allowed decrypt only (ECS execution roles)"
  type        = list(string)
  default     = []
}

variable "deletion_window_in_days" {
  description = "Waiting period before a scheduled key deletion completes"
  type        = number
  default     = 30
}
