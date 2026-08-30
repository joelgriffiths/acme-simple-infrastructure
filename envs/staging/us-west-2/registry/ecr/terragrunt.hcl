include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform { source = "${get_repo_root()}//modules/ecr" }

locals {
  env = include.root.locals.env
  app = read_terragrunt_config("${get_terragrunt_dir()}/app_config.hcl").locals
}

dependency "kms" {
  config_path = "../../security/kms"
  mock_outputs = {
    key_arn = "arn:aws:kms:${include.root.locals.region.region}:${include.root.locals.env.account_id}:key/mock"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  name_prefix      = local.env.project_prefix
  account_id       = local.env.account_id
  repository_names = local.app.repository_names
  kms_key_arn      = dependency.kms.outputs.key_arn

  force_delete = local.env.ecr_force_delete
}
