# No-show rebooking queue. Component-level: the same in every environment.
#
# Separate from the reminders queue on purpose. A rebooking send failing because the SMS
# provider is down must not stall time-sensitive appointment reminders behind it, and the
# two have different urgency, so they get different backlog thresholds in the monitors.
locals {
  queue_suffix = "rebooking"

  visibility_timeout_seconds = 60
  max_receive_count          = 5
}
