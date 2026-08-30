locals {
  service_key         = "admin"
  image_repo          = "admin"
  image_tag           = "bootstrap"
  container_port      = 3000
  health_check_path   = "/healthz"
  listener_priority   = 130
  session_cookie_name = "acme_admin_session"

  datadog_log_source = "nodejs"

  ssm_secret_keys = {
    SESSION_COOKIE_SECRET = "app/session-cookie-secret"
  }

  command = null
}
