include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform { source = "${get_repo_root()}//modules/datadog-monitors" }

locals {
  env    = include.root.locals.env
  config = include.root.locals.config

  mock_account = include.root.locals.env.account_id
  mock_region  = include.root.locals.region.region
}

# Datadog credentials come from DD_API_KEY / DD_APP_KEY in the environment, never from
# code or state. Source them from envs/<env>/secrets/ before running this unit.
generate "datadog_provider" {
  path      = "datadog_provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOT
    provider "datadog" {
      api_url  = "https://api.${local.env.datadog.site}/"
      validate = true
    }
  EOT
}

# Customer-visible traffic. The api and admin services sit behind the internal ALB, but
# their failures surface here too: the patient and clinician sites call the api, so an api
# outage shows up as 5xx on the public load balancer.
dependency "alb_public" {
  config_path                             = "../../edge/alb-public"
  mock_outputs                            = { arn_suffix = "app/mock-public/0123456789abcdef" }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

# Watched separately for one thing only: whether anything is answering at all. An internal
# ALB with no healthy targets means api and admin are down, and no public request has to
# fail for that to be true.
dependency "alb_internal" {
  config_path                             = "../../edge/alb-internal"
  mock_outputs                            = { arn_suffix = "app/mock-internal/0123456789abcdef" }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}
dependency "rds" {
  config_path                             = "../../data/rds"
  mock_outputs                            = { identifier = "mock-pg" }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}
dependency "sqs_reminders" {
  config_path                             = "../../data/sqs/reminders"
  mock_outputs                            = { queue_name = "mock-reminders", dlq_name = "mock-reminders-dlq" }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}
dependency "sqs_rebooking" {
  config_path                             = "../../data/sqs/rebooking"
  mock_outputs                            = { queue_name = "mock-rebooking", dlq_name = "mock-rebooking-dlq" }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}
dependency "worker" {
  config_path                             = "../../compute/ecs/worker"
  mock_outputs                            = { service_name = "mock-worker" }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  env     = local.env.datadog.env_tag
  project = local.config.project

  page_target   = local.env.datadog.page_target
  notify_target = local.env.datadog.notify_target

  load_balancer_name          = dependency.alb_public.outputs.arn_suffix
  internal_load_balancer_name = dependency.alb_internal.outputs.arn_suffix
  db_instance_identifier      = dependency.rds.outputs.identifier
  # Both async pipelines get a dead-letter alarm and a backlog-age alarm. Reminders are the
  # tighter of the two: a reminder that arrives after the appointment is worthless, while a
  # rebooking offer an hour late is still useful.
  queues = {
    reminders = {
      label           = "Reminder"
      queue_name      = dependency.sqs_reminders.outputs.queue_name
      dlq_name        = dependency.sqs_reminders.outputs.dlq_name
      max_age_seconds = 900
    }
    rebooking = {
      label           = "No-show rebooking"
      queue_name      = dependency.sqs_rebooking.outputs.queue_name
      dlq_name        = dependency.sqs_rebooking.outputs.dlq_name
      max_age_seconds = 3600
    }
  }
  worker_service_name = dependency.worker.outputs.service_name

  # Staging keeps every monitor and every dashboard, and pages nobody.
  permanent_downtime = local.env.datadog.permanent_downtime
  create_slo         = local.env.datadog.create_slo
  notify_no_data     = local.env.datadog.notify_no_data
}
