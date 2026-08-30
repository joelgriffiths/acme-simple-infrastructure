include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform { source = "${get_repo_root()}//modules/rds" }

locals {
  env = include.root.locals.env
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

inputs = {
  name       = local.env.project_prefix
  vpc_id     = dependency.vpc.outputs.vpc_id
  subnet_ids = dependency.vpc.outputs.private_subnet_ids
  # CIDR-scoped ingress (VPC private range) to keep the dependency graph acyclic.
  allowed_cidr_blocks = [dependency.vpc.outputs.vpc_cidr]

  instance_class               = local.env.rds.instance_class
  allocated_storage            = local.env.rds.allocated_storage
  multi_az                     = local.env.rds.multi_az
  backup_retention_period      = local.env.rds.backup_retention_period
  deletion_protection          = local.env.rds.deletion_protection
  skip_final_snapshot          = local.env.rds.skip_final_snapshot
  performance_insights_enabled = local.env.rds.performance_insights
}
