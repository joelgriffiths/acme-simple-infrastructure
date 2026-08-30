# Root Terragrunt config. Every unit does:
#
#   include "root" { path = find_in_parent_folders("root.hcl"), expose = true }
#
# and then reads its environment via include.root.locals.{config,env,region}. Units must
# never hardcode an environment-specific value -- the promotion pipeline copies
# terragrunt.hcl verbatim between environments. See CLAUDE.md.
locals {
  config = read_terragrunt_config(find_in_parent_folders("config.hcl")).locals
  env    = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  region = read_terragrunt_config(find_in_parent_folders("region.hcl")).locals
}

# One AWS provider, pinned to the expected account, with default tags on everything.
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "aws" {
      region              = "${local.region.region}"
      profile             = "${local.env.aws_profile}"
      allowed_account_ids = ["${local.env.account_id}"]

      default_tags {
        tags = {
          Project     = "${local.config.project}"
          Environment = "${local.env.environment}"
          ManagedBy   = "terraform"
        }
      }
    }
  EOF
}

generate "versions" {
  path      = "versions.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    terraform {
      required_version = ">= 1.5.0"
      required_providers {
        aws = {
          source  = "hashicorp/aws"
          version = "~> 6.0"
        }
        random = {
          source  = "hashicorp/random"
          version = "~> 3.6"
        }
      }
    }
  EOF
}

# Remote state in S3, locked with DynamoDB, in the environment's OWN account. Key derives
# from the unit's path so it is unique and predictable. Bucket + table are created once per
# environment by envs/bootstrap/<env>.
remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket         = local.env.state_bucket
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = local.region.region
    encrypt        = true
    dynamodb_table = local.env.lock_table
    profile        = local.env.aws_profile
  }
}
