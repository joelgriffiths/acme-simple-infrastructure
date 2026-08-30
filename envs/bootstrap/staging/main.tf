# Terraform state backend for the staging environment, in the staging account.
# Applied once, with a local backend:  terraform init && terraform apply
#
# Values duplicated from config.hcl by necessity: plain Terraform cannot read Terragrunt
# locals. Keep them in sync. See ../README.md.
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

provider "aws" {
  region              = var.region
  profile             = var.aws_profile
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = {
      Project     = "acme"
      Environment = "staging"
      ManagedBy   = "terraform"
    }
  }
}

module "backend" {
  source       = "../../../modules/tf-backend"
  state_bucket = var.state_bucket
  lock_table   = var.lock_table
}

output "state_bucket" {
  description = "Set this as state_buckets[\"staging\"] in config.hcl"
  value       = module.backend.state_bucket
}

output "lock_table" {
  description = "Set this as lock_tables[\"staging\"] in config.hcl"
  value       = module.backend.lock_table
}
