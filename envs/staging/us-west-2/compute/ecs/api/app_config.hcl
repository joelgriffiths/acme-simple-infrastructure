locals {
  service_key       = "api"
  image_repo        = "backend"
  image_tag         = "bootstrap"
  container_port    = 8080
  health_check_path = "/health"
  listener_priority = 100

  datadog_log_source = "nodejs"

  ssm_secret_keys = {
    SESSION_JWT_SECRET = "app/session-jwt-secret"
  }

  command = ["node", "dist/index.js", "serve"]
}
