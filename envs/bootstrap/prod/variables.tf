variable "region" {
  type    = string
  default = "us-west-2"
}

variable "aws_profile" {
  type    = string
  default = "acme-prod"
}

variable "account_id" {
  description = "The prod AWS account. Must match config.hcl."
  type        = string
  default     = "730925632418"
}

variable "state_bucket" {
  type    = string
  default = "acme-prod-tfstate-730925632418"
}

variable "lock_table" {
  type    = string
  default = "acme-prod-tf-locks"
}
