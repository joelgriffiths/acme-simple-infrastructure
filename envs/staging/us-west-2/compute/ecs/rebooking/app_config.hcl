locals {
  service_key = "rebooking"
  image_repo  = "backend"
  image_tag   = "bootstrap"

  datadog_log_source = "nodejs"

  ssm_secret_keys = {
    SMS_API_KEY   = "sms-provider/api-key"
    EMAIL_API_KEY = "email-provider/api-key"
  }

  command = ["node", "dist/index.js", "consume", "rebooking"]
}
