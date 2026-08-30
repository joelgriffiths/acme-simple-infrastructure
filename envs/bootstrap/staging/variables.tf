variable "region" {
  type    = string
  default = "us-west-2"
}

variable "aws_profile" {
  type    = string
  default = "acme-staging"
}

variable "account_id" {
  description = "The staging AWS account. Must match config.hcl."
  type        = string
  default     = "491803677147"
}

variable "state_bucket" {
  type    = string
  default = "acme-staging-tfstate-491803677147"
}

variable "lock_table" {
  type    = string
  default = "acme-staging-tf-locks"
}
