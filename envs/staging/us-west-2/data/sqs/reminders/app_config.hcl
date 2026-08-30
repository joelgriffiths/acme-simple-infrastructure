# Reminder queue tuning. Component-level: the same in every environment.
locals {
  queue_suffix = "reminders"

  # Visibility timeout must exceed the worker's slowest provider call plus retries.
  visibility_timeout_seconds = 60
  max_receive_count          = 5
}
