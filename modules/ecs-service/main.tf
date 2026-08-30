# Reusable Fargate service. Two shapes, one module:
#   - ALB-attached (api, web): attach_alb=true creates a target group + host-based
#     listener rule and wires the service's load_balancer block.
#   - Standalone (worker): attach_alb=false, no target group, egress-only task SG.
# Each service gets its own task SG, execution role, and task role (least privilege).
#
# Optionally runs two sidecars: the Datadog agent (metrics + APM) and a Fluent Bit log
# router that scrubs patient data before anything leaves the VPC. See the PII scrubbing
# note below and modules/ecs-service/fluent-bit/README.md.

data "aws_region" "current" {}

locals {
  awslogs_group = "/ecs/${var.name}"

  # --- PII scrubbing for APM ---
  # Acme stores patient names, phone numbers, and email addresses. None of that may reach
  # Datadog. Span tags are rewritten inside the agent, in our VPC, before egress. This is
  # a backstop, not a licence to put patient data in spans: the app should not tag them in
  # the first place. Log scrubbing is handled separately by the Fluent Bit config.
  apm_replace_tags = jsonencode([
    {
      name    = "*"
      pattern = "(?i)[a-z0-9._%+-]+@[a-z0-9.-]+\\.[a-z]{2,}"
      repl    = "[redacted-email]"
    },
    {
      name    = "*"
      pattern = "\\+?[0-9]{0,2}[ .-]?\\(?[0-9]{3}\\)?[ .-]?[0-9]{3}[ .-]?[0-9]{4}"
      repl    = "[redacted-phone]"
    },
    {
      name    = "http.url"
      pattern = "(?i)(patient|phone|email|name|dob)=[^&]+"
      repl    = "[redacted-query]"
    },
  ])

  datadog_agent_container = var.datadog_enabled ? [{
    name              = "datadog-agent"
    image             = var.datadog_agent_image
    essential         = true
    memoryReservation = var.datadog_agent_memory
    cpu               = var.datadog_agent_cpu
    environment = [
      { name = "ECS_FARGATE", value = "true" },
      { name = "DD_SITE", value = var.datadog_site },
      { name = "DD_ENV", value = var.datadog_env },
      { name = "DD_SERVICE", value = var.name },
      { name = "DD_TAGS", value = "env:${var.datadog_env} service:${var.name}" },
      # Logs travel via Fluent Bit, not the agent, so they can be scrubbed first.
      { name = "DD_LOGS_ENABLED", value = "false" },
      { name = "DD_APM_ENABLED", value = tostring(var.datadog_apm_enabled) },
      { name = "DD_APM_NON_LOCAL_TRAFFIC", value = "true" },
      { name = "DD_DOGSTATSD_NON_LOCAL_TRAFFIC", value = "true" },
      # Strip identifiers out of URLs and query strings before they become span resources.
      { name = "DD_APM_OBFUSCATION_HTTP_REMOVE_QUERY_STRING", value = "true" },
      { name = "DD_APM_OBFUSCATION_HTTP_REMOVE_PATHS_WITH_DIGITS", value = "true" },
      { name = "DD_APM_REPLACE_TAGS", value = local.apm_replace_tags },
    ]
    secrets = [{ name = "DD_API_KEY", valueFrom = var.datadog_api_key_parameter_arn }]
    healthCheck = {
      command     = ["CMD-SHELL", "agent health"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 15
    }
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = local.awslogs_group
        "awslogs-region"        = data.aws_region.current.region
        "awslogs-stream-prefix" = "datadog-agent"
      }
    }
  }] : []

  # Fluent Bit runs a custom image built from modules/ecs-service/fluent-bit/ that carries
  # the scrubbing filters. Stock aws-for-fluent-bit will not do: on Fargate the only way to
  # supply a Fluent Bit config file is to bake it into the image.
  log_router_container = var.datadog_enabled ? [{
    name              = "log-router"
    image             = var.datadog_log_router_image
    essential         = true
    memoryReservation = 128
    firelensConfiguration = {
      type = "fluentbit"
      options = {
        "enable-ecs-log-metadata" = "true"
        "config-file-type"        = "file"
        "config-file-value"       = var.datadog_log_scrub_config_path
      }
    }
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = local.awslogs_group
        "awslogs-region"        = data.aws_region.current.region
        "awslogs-stream-prefix" = "log-router"
      }
    }
  }] : []

  # App logs go through Fluent Bit when Datadog is on, straight to CloudWatch otherwise.
  # Built as a one-element tuple rather than a ternary: the two log drivers have different
  # option sets, and a ternary would force them to share a type.
  app_log_configuration = concat(
    var.datadog_enabled ? [{
      logDriver = "awsfirelens"
      options = {
        Name           = "datadog"
        Host           = "http-intake.logs.${var.datadog_site}"
        TLS            = "on"
        provider       = "ecs"
        dd_service     = var.name
        dd_source      = var.datadog_log_source
        dd_tags        = "env:${var.datadog_env},service:${var.name}"
        dd_message_key = "log"
      }
      secretOptions = [{ name = "apikey", valueFrom = var.datadog_api_key_parameter_arn }]
    }] : [],
    var.datadog_enabled ? [] : [{
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = local.awslogs_group
        "awslogs-region"        = data.aws_region.current.region
        "awslogs-stream-prefix" = "ecs"
      }
    }],
  )[0]

  # Secrets Manager entries and SSM parameters are injected identically by ECS.
  all_secrets = merge(var.secrets, var.ssm_parameters)

  datadog_app_env = var.datadog_enabled ? {
    DD_ENV        = var.datadog_env
    DD_SERVICE    = var.name
    DD_AGENT_HOST = "127.0.0.1"
  } : {}

  # command and entrypoint are omitted entirely when unset rather than serialised as null,
  # which ECS rejects. The worker in particular usually needs an explicit command.
  app_overrides = merge(
    var.command == null ? {} : { command = var.command },
    var.entrypoint == null ? {} : { entryPoint = var.entrypoint },
    var.working_directory == null ? {} : { workingDirectory = var.working_directory },
  )

  app_container = merge(local.app_overrides, {
    name      = var.name
    image     = var.image
    essential = true
    portMappings = var.attach_alb ? [{
      containerPort = var.container_port
      protocol      = "tcp"
    }] : []
    environment      = [for k, v in merge(var.environment, local.datadog_app_env) : { name = k, value = v }]
    secrets          = [for k, v in local.all_secrets : { name = k, valueFrom = v }]
    logConfiguration = local.app_log_configuration
    dependsOn = var.datadog_enabled ? [
      { containerName = "datadog-agent", condition = "HEALTHY" },
      { containerName = "log-router", condition = "START" },
    ] : []
  })

  containers = concat([local.app_container], local.datadog_agent_container, local.log_router_container)
}

# --- Logs ---
resource "aws_cloudwatch_log_group" "this" {
  name              = local.awslogs_group
  retention_in_days = var.log_retention_days
  tags              = { Name = var.name }
}

# --- Task security group ---
resource "aws_security_group" "task" {
  name        = "${var.name}-task"
  description = "Fargate task SG for ${var.name}"
  vpc_id      = var.vpc_id

  egress {
    description = "All outbound (NAT to internet, RDS, SQS, third-party APIs)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-task" }
}

# Ingress only for ALB-attached services, only from the ALB SG, only the container port.
resource "aws_security_group_rule" "from_alb" {
  count                    = var.attach_alb ? 1 : 0
  type                     = "ingress"
  security_group_id        = aws_security_group.task.id
  from_port                = var.container_port
  to_port                  = var.container_port
  protocol                 = "tcp"
  source_security_group_id = var.alb_security_group_id
  description              = "App traffic from the ALB"
}

# --- IAM: execution role (pull image, read secrets, write logs) ---
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.name}-exec"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = { Name = "${var.name}-exec" }
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Read exactly the Secrets Manager entries and SSM parameters this task injects, and
# decrypt only with this environment's secrets key. Nothing wildcarded.
data "aws_iam_policy_document" "execution_secrets" {
  dynamic "statement" {
    for_each = length(var.secret_arns) > 0 ? [1] : []
    content {
      sid       = "ReadSecretsManager"
      effect    = "Allow"
      actions   = ["secretsmanager:GetSecretValue"]
      resources = var.secret_arns
    }
  }

  dynamic "statement" {
    for_each = length(var.ssm_parameter_arns) > 0 ? [1] : []
    content {
      sid       = "ReadSsmParameters"
      effect    = "Allow"
      actions   = ["ssm:GetParameters"]
      resources = var.ssm_parameter_arns
    }
  }

  dynamic "statement" {
    for_each = var.secrets_kms_key_arn == null ? [] : [1]
    content {
      sid       = "DecryptSecureStrings"
      effect    = "Allow"
      actions   = ["kms:Decrypt"]
      resources = [var.secrets_kms_key_arn]
    }
  }
}

resource "aws_iam_role_policy" "execution_secrets" {
  count  = length(var.secret_arns) + length(var.ssm_parameter_arns) > 0 ? 1 : 0
  name   = "read-secrets"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution_secrets.json
}

# --- IAM: task role (the app's own AWS permissions, e.g. worker -> SQS) ---
resource "aws_iam_role" "task" {
  name               = "${var.name}-task"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = { Name = "${var.name}-task" }
}

resource "aws_iam_role_policy" "task_inline" {
  count  = var.task_policy_json == null ? 0 : 1
  name   = "app"
  role   = aws_iam_role.task.id
  policy = var.task_policy_json
}

# --- Task definition ---
# NOTE: var.cpu / var.memory cover the whole task, sidecars included. When Datadog is on,
# budget roughly 256 extra CPU units and 512 extra MiB on top of the app's own needs.
resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode(local.containers)

  tags = { Name = var.name }
}

# --- ALB target group + host rule (ALB-attached services only) ---
resource "aws_lb_target_group" "this" {
  count       = var.attach_alb ? 1 : 0
  name        = "${var.name}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = var.health_check_path
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = { Name = "${var.name}-tg" }
}

resource "aws_lb_listener_rule" "host" {
  count        = var.attach_alb ? 1 : 0
  listener_arn = var.alb_listener_arn
  priority     = var.listener_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[0].arn
  }

  condition {
    host_header {
      values = var.host_headers
    }
  }
}

# --- Service ---
resource "aws_ecs_service" "this" {
  name            = var.name
  cluster         = var.cluster_arn
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.task.id]
    assign_public_ip = false
  }

  dynamic "load_balancer" {
    for_each = var.attach_alb ? [1] : []
    content {
      target_group_arn = aws_lb_target_group.this[0].arn
      container_name   = var.name
      container_port   = var.container_port
    }
  }

  # Let CI update the image without Terraform reverting it (deploys are out-of-band).
  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  depends_on = [aws_lb_listener_rule.host]
}

# --- Optional target-tracking autoscaling on CPU ---
resource "aws_appautoscaling_target" "this" {
  count              = var.enable_autoscaling ? 1 : 0
  max_capacity       = var.max_count
  min_capacity       = var.min_count
  resource_id        = "service/${var.cluster_name}/${aws_ecs_service.this.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu" {
  count              = var.enable_autoscaling ? 1 : 0
  name               = "${var.name}-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.this[0].resource_id
  scalable_dimension = aws_appautoscaling_target.this[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.this[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = var.cpu_target
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}
