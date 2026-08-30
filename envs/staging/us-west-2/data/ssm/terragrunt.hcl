include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform { source = "${get_repo_root()}//modules/ssm-parameters" }

locals {
  env = include.root.locals.env
  app = read_terragrunt_config("${get_terragrunt_dir()}/app_config.hcl").locals
}

dependency "kms" {
  config_path = "../../security/kms"
  mock_outputs = {
    key_id = "mock-key-id"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  prefix            = local.env.ssm_prefix
  kms_key_id        = dependency.kms.outputs.key_id
  secret_parameters = local.app.secret_parameters
}
