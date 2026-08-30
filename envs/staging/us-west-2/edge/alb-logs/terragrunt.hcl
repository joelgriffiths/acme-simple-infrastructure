include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform { source = "${get_repo_root()}//modules/alb-access-logs" }

locals {
  env = include.root.locals.env
}

dependency "forwarder" {
  config_path = "../../observability/datadog-forwarder"
  mock_outputs = {
    lambda_arn = "arn:aws:lambda:${include.root.locals.region.region}:${include.root.locals.env.account_id}:function:mock"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  bucket_name    = "${local.env.project_prefix}-alb-logs-${local.env.account_id}"
  retention_days = local.env.alb_access_log_retention

  # One bucket, one prefix per load balancer.
  log_prefixes = ["alb-public", "alb-internal"]

  # Every new log file is picked up and shipped to Datadog. S3 stays the durable audit
  # trail; Datadog is the search interface.
  forwarder_lambda_arn = dependency.forwarder.outputs.lambda_arn

  force_destroy = local.env.ecr_force_delete
}
