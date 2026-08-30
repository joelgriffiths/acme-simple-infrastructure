include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform { source = "${get_repo_root()}//modules/ecs-service" }

locals {
  env    = include.root.locals.env
  region = include.root.locals.region
  app    = read_terragrunt_config("${get_terragrunt_dir()}/app_config.hcl").locals

  mock_account = include.root.locals.env.account_id
  mock_region  = include.root.locals.region.region
}

dependency "vpc" {
  config_path                             = "../../../network/vpc"
  mock_outputs                            = { vpc_id = "vpc-mock", private_subnet_ids = ["subnet-m1", "subnet-m2"] }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}
dependency "sqs" {
  config_path = "../../../data/sqs/reminders"
  mock_outputs = {
    queue_url = "https://sqs.${local.mock_region}.amazonaws.com/${local.mock_account}/mock"
    queue_arn = "arn:aws:sqs:${local.mock_region}:${local.mock_account}:mock"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}
dependency "cluster" {
  config_path = "../cluster"
  mock_outputs = {
    cluster_arn  = "arn:aws:ecs:${local.mock_region}:${local.mock_account}:cluster/mock"
    cluster_name = "mock"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}
dependency "rds" {
  config_path = "../../../data/rds"
  mock_outputs = {
    address                = "mock.rds.amazonaws.com"
    db_name                = "acme"
    master_user_secret_arn = "arn:aws:secretsmanager:${local.mock_region}:${local.mock_account}:secret:mock"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}
dependency "ecr" {
  config_path = "../../../registry/ecr"
  mock_outputs = {
    repository_urls = {
      backend      = "${local.mock_account}.dkr.ecr.${local.mock_region}.amazonaws.com/mock/backend"
      "clinic-web" = "${local.mock_account}.dkr.ecr.${local.mock_region}.amazonaws.com/mock/clinic-web"
      admin        = "${local.mock_account}.dkr.ecr.${local.mock_region}.amazonaws.com/mock/admin"
      "fluent-bit" = "${local.mock_account}.dkr.ecr.${local.mock_region}.amazonaws.com/mock/fluent-bit"
    }
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}
dependency "ssm" {
  config_path = "../../../data/ssm"
  mock_outputs = {
    secret_arns = {
      "sms-provider/api-key"      = "arn:aws:ssm:${local.mock_region}:${local.mock_account}:parameter/mock/sms"
      "email-provider/api-key"    = "arn:aws:ssm:${local.mock_region}:${local.mock_account}:parameter/mock/email"
      "datadog/api-key"           = "arn:aws:ssm:${local.mock_region}:${local.mock_account}:parameter/mock/datadog"
      "app/session-jwt-secret"    = "arn:aws:ssm:${local.mock_region}:${local.mock_account}:parameter/mock/session-jwt"
      "app/session-cookie-secret" = "arn:aws:ssm:${local.mock_region}:${local.mock_account}:parameter/mock/session-cookie"
    }
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}
dependency "kms" {
  config_path                             = "../../../security/kms"
  mock_outputs                            = { key_arn = "arn:aws:kms:${local.mock_region}:${local.mock_account}:key/mock" }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  name               = "${local.env.project_prefix}-${local.app.service_key}"
  cluster_arn        = dependency.cluster.outputs.cluster_arn
  cluster_name       = dependency.cluster.outputs.cluster_name
  vpc_id             = dependency.vpc.outputs.vpc_id
  private_subnet_ids = dependency.vpc.outputs.private_subnet_ids

  image         = "${dependency.ecr.outputs.repository_urls[local.app.image_repo]}:${local.app.image_tag}"
  cpu           = local.env.worker.cpu
  memory        = local.env.worker.memory
  desired_count = local.env.worker.desired_count

  attach_alb = false

  log_retention_days = local.env.log_retention_days
  command            = local.app.command

  environment = {
    DB_HOST   = dependency.rds.outputs.address
    DB_NAME   = dependency.rds.outputs.db_name
    DB_PORT   = "5432"
    QUEUE_URL = dependency.sqs.outputs.queue_url
  }

  secrets = {
    DB_USER     = "${dependency.rds.outputs.master_user_secret_arn}:username::"
    DB_PASSWORD = "${dependency.rds.outputs.master_user_secret_arn}:password::"
  }
  secret_arns = [dependency.rds.outputs.master_user_secret_arn]

  ssm_parameters = {
    for env_var, key in local.app.ssm_secret_keys :
    env_var => dependency.ssm.outputs.secret_arns[key]
  }
  ssm_parameter_arns = concat(
    [for key in values(local.app.ssm_secret_keys) : dependency.ssm.outputs.secret_arns[key]],
    [dependency.ssm.outputs.secret_arns["datadog/api-key"]],
  )
  secrets_kms_key_arn = dependency.kms.outputs.key_arn

  task_policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "sqs:ReceiveMessage", "sqs:DeleteMessage",
        "sqs:ChangeMessageVisibility", "sqs:GetQueueAttributes",
      ]
      Resource = dependency.sqs.outputs.queue_arn
    }]
  })

  datadog_enabled               = local.env.datadog.enabled
  datadog_site                  = local.env.datadog.site
  datadog_env                   = local.env.datadog.env_tag
  datadog_apm_enabled           = local.env.datadog.apm_enabled
  datadog_api_key_parameter_arn = dependency.ssm.outputs.secret_arns["datadog/api-key"]
  datadog_log_router_image      = "${dependency.ecr.outputs.repository_urls["fluent-bit"]}:${local.env.datadog.log_router_tag}"
  datadog_log_source            = local.app.datadog_log_source
}
