locals {
  service_key         = "patient"
  image_repo          = "clinic-web"
  image_tag           = "bootstrap"
  container_port      = 3000
  health_check_path   = "/healthz"
  listener_priority   = 110
  session_cookie_name = "acme_patient_session"

  datadog_log_source = "nodejs"

  ssm_secret_keys = {
    SESSION_COOKIE_SECRET = "app/session-cookie-secret"
  }

  command = ["node", "start.mjs", "patient"]
}
