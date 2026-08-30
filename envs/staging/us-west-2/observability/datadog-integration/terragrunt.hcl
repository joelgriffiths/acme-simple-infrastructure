include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform { source = "${get_repo_root()}//modules/datadog-aws-integration" }

locals {
  env = include.root.locals.env
}

inputs = {
  name_prefix = local.env.project_prefix
  external_id = local.env.datadog.aws_integration_external_id
}
