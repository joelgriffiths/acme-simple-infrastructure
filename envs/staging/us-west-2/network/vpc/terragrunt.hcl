include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform { source = "${get_repo_root()}//modules/vpc" }

locals {
  env    = include.root.locals.env
  region = include.root.locals.region
}

inputs = {
  name                 = local.env.project_prefix
  cidr_block           = local.region.vpc_cidr
  azs                  = local.region.azs
  public_subnet_cidrs  = local.region.public_subnet_cidrs
  private_subnet_cidrs = local.region.private_subnet_cidrs
  single_nat_gateway   = local.env.single_nat_gateway
}
