include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform { source = "${get_repo_root()}//modules/bastion" }

locals {
  env    = include.root.locals.env
  region = include.root.locals.region
}

dependency "vpc" {
  config_path = "../../network/vpc"
  mock_outputs = {
    vpc_id            = "vpc-mock"
    vpc_cidr          = "10.0.0.0/16"
    public_subnet_ids = ["subnet-mock1", "subnet-mock2"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  name      = local.env.project_prefix
  vpc_id    = dependency.vpc.outputs.vpc_id
  vpc_cidr  = dependency.vpc.outputs.vpc_cidr
  subnet_id = dependency.vpc.outputs.public_subnet_ids[0]

  instance_type   = local.env.bastion.instance_type
  ingress_cidrs   = local.env.bastion.ingress_cidrs
  ssh_public_keys = local.env.bastion.ssh_public_keys
}
