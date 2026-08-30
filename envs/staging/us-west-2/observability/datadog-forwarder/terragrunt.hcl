include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform { source = "${get_repo_root()}//modules/datadog-forwarder" }

locals {
  env = include.root.locals.env
}

dependency "kms" {
  config_path                             = "../../security/kms"
  mock_outputs                            = { key_id = "mock-key-id" }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  name         = local.env.project_prefix
  datadog_site = local.env.datadog.site
  kms_key_id   = dependency.kms.outputs.key_id
}
