variable "prefix" {
  description = "Parameter namespace, e.g. /acme/staging"
  type        = string
}

variable "kms_key_id" {
  description = "KMS key encrypting SecureString parameters (the environment's secrets key)"
  type        = string
}

variable "secret_parameters" {
  description = "Short name => description. Containers only; values are written out of band by the SOPS pipeline."
  type        = map(string)
  default     = {}
}

variable "config_parameters" {
  description = "Short name => value. Non-secret configuration Terraform already knows."
  type        = map(string)
  default     = {}
}
