include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform { source = "${get_repo_root()}//modules/waf" }

locals {
  env    = include.root.locals.env
  region = include.root.locals.region

  # env.hcl tunes by role; region.hcl owns the hostnames. Joined here so neither file has
  # to know about the other.
  #
  # Driven from region.hcl's public_hosts rather than from the rules map, so a hostname
  # cannot be made public without also acquiring WAF rules: if a public host has no entry in
  # env.hcl, the lookup below fails the plan with a missing-key error. That is deliberate.
  # Internal hostnames never appear here at all; the internal ALB has no public address.
  public_roles = {
    for role, host in local.region.hosts :
    role => host if contains(local.region.public_hosts, host)
  }

  host_rules = {
    for role, host in local.public_roles :
    host => local.env.waf.rules[role]
  }
}

dependency "alb" {
  config_path = "../alb-public"
  mock_outputs = {
    alb_arn = "arn:aws:elasticloadbalancing:${include.root.locals.region.region}:${include.root.locals.env.account_id}:loadbalancer/app/mock/0123456789abcdef"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  name       = local.env.project_prefix
  alb_arn    = dependency.alb.outputs.alb_arn
  host_rules = local.host_rules

  enable_logging     = local.env.waf.enabled
  log_retention_days = local.env.waf.log_retention_days
}
