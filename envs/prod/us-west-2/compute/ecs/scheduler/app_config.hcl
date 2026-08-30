locals {
  service_key = "scheduler"
  image_repo  = "backend"
  image_tag   = "bootstrap"

  datadog_log_source = "nodejs"

  ssm_secret_keys = {}

  command = ["node", "dist/index.js", "schedule"]
}
