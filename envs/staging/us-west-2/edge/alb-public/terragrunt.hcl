include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform { source = "${get_repo_root()}//modules/alb" }

locals {
  env = include.root.locals.env
}

dependency "vpc" {
  config_path = "../../network/vpc"
  mock_outputs = {
    vpc_id            = "vpc-mock"
    public_subnet_ids = ["subnet-mock1", "subnet-mock2"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "acm" {
  config_path = "../acm-public"
  mock_outputs = {
    certificate_arn = "arn:aws:acm:${include.root.locals.region.region}:${include.root.locals.env.account_id}:certificate/mock"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "logs" {
  config_path = "../alb-logs"
  mock_outputs = {
    bucket_name  = "mock-alb-logs"
    log_prefixes = ["alb-public", "alb-internal"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

# Serves book.* and clinic.* from the public subnets. This is the only resource in the
# design with an address on the internet, and the WAF is attached to it.
inputs = {
  name            = "${local.env.project_prefix}-public"
  vpc_id          = dependency.vpc.outputs.vpc_id
  subnet_ids      = dependency.vpc.outputs.public_subnet_ids
  certificate_arn = dependency.acm.outputs.certificate_arn

  internal                   = false
  ingress_cidrs              = local.env.alb_ingress_cidrs
  enable_deletion_protection = local.env.alb_deletion_protection

  access_logs_bucket = dependency.logs.outputs.bucket_name
  access_logs_prefix = "alb-public"
}
