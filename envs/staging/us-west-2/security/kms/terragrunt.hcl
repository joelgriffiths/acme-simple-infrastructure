include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform { source = "${get_repo_root()}//modules/kms-secrets" }

locals {
  env = include.root.locals.env
}

inputs = {
  name_prefix = local.env.project_prefix
  environment = local.env.environment
}
