include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform { source = "${get_repo_root()}//modules/alb" }

locals {
  env    = include.root.locals.env
  region = include.root.locals.region
}

dependency "vpc" {
  config_path = "../../network/vpc"
  mock_outputs = {
    vpc_id             = "vpc-mock"
    vpc_cidr           = "10.0.0.0/16"
    private_subnet_ids = ["subnet-mock1", "subnet-mock2"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "acm" {
  config_path = "../acm-private"
  mock_outputs = {
    certificate_arn = "arn:aws:acm:${include.root.locals.region.region}:${include.root.locals.env.account_id}:certificate/mock-internal"
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

# Serves api.* and admin.* with no public address, in the private subnets, on a certificate
# from our own CA. Ingress is the VPC range only: nothing outside the VPC can route here at
# all, and the security group says so explicitly rather than relying on that.
inputs = {
  name            = "${local.env.project_prefix}-internal"
  vpc_id          = dependency.vpc.outputs.vpc_id
  subnet_ids      = dependency.vpc.outputs.private_subnet_ids
  certificate_arn = dependency.acm.outputs.certificate_arn

  internal                   = true
  ingress_cidrs              = [dependency.vpc.outputs.vpc_cidr]
  enable_deletion_protection = local.env.alb_deletion_protection

  access_logs_bucket = dependency.logs.outputs.bucket_name
  access_logs_prefix = "alb-internal"
}
