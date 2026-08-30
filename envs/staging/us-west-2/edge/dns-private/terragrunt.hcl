include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform { source = "${get_repo_root()}//modules/route53-private" }

locals {
  env    = include.root.locals.env
  region = include.root.locals.region
}

dependency "vpc" {
  config_path                             = "../../network/vpc"
  mock_outputs                            = { vpc_id = "vpc-mock" }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "alb" {
  config_path = "../alb-internal"
  mock_outputs = {
    alb_dns_name = "internal-mock.elb.amazonaws.com"
    alb_zone_id  = "Z0MOCK"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

# Private hosted zone associated with this VPC. The association is what makes the internal
# names resolve; without it the zone answers nobody. Resolution works from anything in the
# VPC, which includes the ECS tasks and the bastion.
inputs = {
  name        = local.env.project_prefix
  domain_name = local.region.private_domain
  vpc_id      = dependency.vpc.outputs.vpc_id
  vpc_region  = local.region.region

  hostnames    = local.region.internal_hosts
  alb_dns_name = dependency.alb.outputs.alb_dns_name
  alb_zone_id  = dependency.alb.outputs.alb_zone_id

  force_destroy = local.env.ecr_force_delete
}
