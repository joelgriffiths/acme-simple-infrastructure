output "monitor_ids" {
  description = "Monitor key => Datadog monitor ID"
  value       = { for k, m in datadog_monitor.this : k => m.id }
}

output "slo_id" {
  description = "Booking API availability SLO ID, null when not created"
  value       = var.create_slo ? datadog_service_level_objective.api_availability[0].id : null
}
