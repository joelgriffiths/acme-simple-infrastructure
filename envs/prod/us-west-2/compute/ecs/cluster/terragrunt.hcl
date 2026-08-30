include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform { source = "${get_repo_root()}//modules/ecs-cluster" }

locals {
  env = include.root.locals.env
}

inputs = {
  name = local.env.project_prefix
}
