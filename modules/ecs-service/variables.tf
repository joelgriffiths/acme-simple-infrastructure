variable "name" {
  description = "Service name (e.g. acme-staging-api)"
  type        = string
}

variable "cluster_arn" {
  description = "ECS cluster ARN"
  type        = string
}

variable "cluster_name" {
  description = "ECS cluster name (for autoscaling resource_id)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets for the tasks"
  type        = list(string)
}

variable "image" {
  description = "Container image (ECR repo:tag). Placeholder is fine; CI updates it."
  type        = string
}

variable "container_port" {
  description = "Port the container listens on (ALB-attached services)"
  type        = number
  default     = 8080
}

variable "cpu" {
  description = "Fargate task CPU units (256/512/1024/...)"
  type        = number
  default     = 512
}

variable "memory" {
  description = "Fargate task memory (MiB)"
  type        = number
  default     = 1024
}

variable "desired_count" {
  description = "Initial task count"
  type        = number
  default     = 2
}

variable "environment" {
  description = "Plain (non-secret) environment variables"
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Secret env vars: name => Secrets Manager ARN (optionally with :json-key::)"
  type        = map(string)
  default     = {}
}

variable "secret_arns" {
  description = "Secret ARNs the execution role may read (usually values() of var.secrets)"
  type        = list(string)
  default     = []
}

variable "task_policy_json" {
  description = "Optional IAM policy JSON attached to the task role (e.g. SQS access for the worker)"
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "CloudWatch log retention"
  type        = number
  default     = 30
}

# --- ALB attachment ---
variable "attach_alb" {
  description = "Attach to the ALB (true for api/web, false for worker)"
  type        = bool
  default     = false
}

variable "alb_listener_arn" {
  description = "HTTPS listener ARN to attach a host rule to"
  type        = string
  default     = null
}

variable "alb_security_group_id" {
  description = "ALB SG allowed to reach the task"
  type        = string
  default     = null
}

variable "host_headers" {
  description = "Host header(s) routed to this service (e.g. [\"api.acme.example\"])"
  type        = list(string)
  default     = []
}

variable "listener_priority" {
  description = "Listener rule priority (unique per ALB)"
  type        = number
  default     = 100
}

variable "health_check_path" {
  description = "Health check path for the target group"
  type        = string
  default     = "/health"
}

# --- Autoscaling ---
variable "enable_autoscaling" {
  description = "Enable CPU target-tracking autoscaling"
  type        = bool
  default     = false
}

variable "min_count" {
  description = "Min tasks when autoscaling"
  type        = number
  default     = 2
}

variable "max_count" {
  description = "Max tasks when autoscaling"
  type        = number
  default     = 6
}

variable "cpu_target" {
  description = "Target average CPU %% for autoscaling"
  type        = number
  default     = 60
}

# --- SSM Parameter Store secrets ---
# Third-party API keys live in SSM SecureString, encrypted with the environment's KMS key.
# Database master credentials stay in Secrets Manager (var.secrets / var.secret_arns) so
# they keep RDS-managed rotation. The split is deliberate; see ARCHITECTURE.md.
variable "ssm_parameters" {
  description = "Secret env vars sourced from SSM: env var name => parameter ARN"
  type        = map(string)
  default     = {}
}

variable "ssm_parameter_arns" {
  description = "SSM parameter ARNs the execution role may read (usually values() of var.ssm_parameters)"
  type        = list(string)
  default     = []
}

variable "secrets_kms_key_arn" {
  description = "KMS key the execution role may use to decrypt SecureString parameters"
  type        = string
  default     = null
}

# --- Datadog sidecars ---
variable "datadog_enabled" {
  description = "Run the Datadog agent + scrubbing log router alongside the app container"
  type        = bool
  default     = false
}

variable "datadog_site" {
  description = "Datadog site, e.g. datadoghq.com or datadoghq.eu"
  type        = string
  default     = "datadoghq.com"
}

variable "datadog_env" {
  description = "Value for the DD_ENV unified tag (staging, prod)"
  type        = string
  default     = null
}

variable "datadog_api_key_parameter_arn" {
  description = "SSM SecureString ARN holding the Datadog API key"
  type        = string
  default     = null
}

variable "datadog_apm_enabled" {
  description = "Enable APM trace collection. Requires the app to be instrumented."
  type        = bool
  default     = false
}

variable "datadog_agent_image" {
  description = "Datadog agent image"
  type        = string
  default     = "public.ecr.aws/datadog/agent:7"
}

variable "datadog_agent_cpu" {
  description = "CPU units reserved for the agent sidecar (comes out of var.cpu)"
  type        = number
  default     = 128
}

variable "datadog_agent_memory" {
  description = "MiB reserved for the agent sidecar (comes out of var.memory)"
  type        = number
  default     = 256
}

variable "datadog_log_router_image" {
  description = "Fluent Bit image carrying the scrubbing config, built from modules/ecs-service/fluent-bit/"
  type        = string
  default     = null
}

variable "datadog_log_scrub_config_path" {
  description = "Path to the scrubbing config inside the log router image"
  type        = string
  default     = "/fluent-bit/etc/scrub.conf"
}

variable "datadog_log_source" {
  description = "Datadog log source tag, used to pick a parsing pipeline"
  type        = string
  default     = "ecs"
}

# --- Container entrypoint overrides ---
# Unset by default so the image's own CMD/ENTRYPOINT wins. Set command when one image
# serves several roles, which is the usual reason a worker differs from an api.
variable "command" {
  description = "Override the image CMD, e.g. [\"node\", \"dist/worker.js\"]"
  type        = list(string)
  default     = null
}

variable "entrypoint" {
  description = "Override the image ENTRYPOINT"
  type        = list(string)
  default     = null
}

variable "working_directory" {
  description = "Override the container working directory"
  type        = string
  default     = null
}
