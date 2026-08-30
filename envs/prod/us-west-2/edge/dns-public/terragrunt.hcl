include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform { source = "${get_repo_root()}//modules/route53" }

locals {
  region = include.root.locals.region
}

dependency "alb" {
  config_path = "../alb-public"
  mock_outputs = {
    alb_dns_name = "mock.elb.amazonaws.com"
    alb_zone_id  = "Z0MOCK"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  zone_id      = local.region.public_zone_id
  hostnames    = local.region.public_hosts
  alb_dns_name = dependency.alb.outputs.alb_dns_name
  alb_zone_id  = dependency.alb.outputs.alb_zone_id
}
