variable "name_prefix" {
  description = "Repository namespace, e.g. acme-staging (repos become acme-staging/api)"
  type        = string
}

variable "account_id" {
  description = "AWS account that owns this registry and pulls from it"
  type        = string
}

variable "repository_names" {
  description = "Short service names to create repositories for, e.g. [\"api\", \"web\", \"worker\"]"
  type        = list(string)
}

variable "kms_key_arn" {
  description = "KMS key used to encrypt image layers at rest"
  type        = string
}

variable "image_tag_mutability" {
  description = "IMMUTABLE means a pushed tag can never be repointed. Keep it immutable."
  type        = string
  default     = "IMMUTABLE"
}

variable "retained_image_count" {
  description = "How many tagged images to keep per repository"
  type        = number
  default     = 30
}

variable "untagged_expiry_days" {
  description = "Days before an untagged image is expired"
  type        = number
  default     = 3
}

variable "force_delete" {
  description = "Allow destroying a repository that still holds images (staging only)"
  type        = bool
  default     = false
}
