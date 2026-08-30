# The environment's SSM parameter namespace.
#
# secret_parameters are CONTAINERS ONLY. Terraform creates them with a placeholder and then
# ignores the value forever. Real values come from envs/<env>/secrets/*.enc.yaml via SOPS,
# written with `make secrets-push ENV=<env>`.
#
# Database master credentials are deliberately absent: they stay RDS-managed in Secrets
# Manager so they keep native rotation. See ARCHITECTURE.md.
locals {
  secret_parameters = {
    # Third-party providers. Consumed by the worker (reminders) and rebooking (no-shows).
    "sms-provider/api-key"   = "Third-party SMS provider API key"
    "email-provider/api-key" = "Third-party email provider API key"

    # Observability. Read by the agent and log router sidecars in every service.
    "datadog/api-key" = "Datadog API key, used by the agent and log router sidecars"

    # Application session material.
    #   session-jwt-secret     signs the tokens the api issues and the frontends present
    #   session-cookie-secret  signs the browser session cookies in the three web apps
    # Kept apart so rotating browser sessions does not invalidate every API token.
    "app/session-jwt-secret"    = "Signing key for API session tokens"
    "app/session-cookie-secret" = "Signing key for browser session cookies (patient, clinician, admin)"
  }
}
