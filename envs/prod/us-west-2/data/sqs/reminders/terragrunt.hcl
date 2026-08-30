include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform { source = "${get_repo_root()}//modules/sqs" }

locals {
  env = include.root.locals.env
  app = read_terragrunt_config("${get_terragrunt_dir()}/app_config.hcl").locals
}

inputs = {
  name                       = "${local.env.project_prefix}-${local.app.queue_suffix}"
  visibility_timeout_seconds = local.app.visibility_timeout_seconds
  max_receive_count          = local.app.max_receive_count
}
