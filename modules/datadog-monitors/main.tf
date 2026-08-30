# Datadog monitors for Acme, defined as data rather than as a wall of resource blocks.
#
# The list is short on purpose. Four engineers cannot carry twenty pagers, so exactly the
# monitors that mean "a clinic or a patient is being harmed right now" page, and everything
# else goes to Slack. Alerts nobody acts on train people to ignore the ones that matter,
# which is worse than having no monitoring at all.
#
# Everything here comes from AWS integration metrics, so it works without the application
# being instrumented. APM-based monitors come later, once the agent sidecars have traces.
#
# Each entry carries both the full query and its `critical` threshold. Datadog needs the
# threshold as a separate field and the query is the readable artifact, so the number
# appears twice: keep them in sync.

terraform {
  required_providers {
    datadog = {
      source  = "DataDog/datadog"
      version = "~> 3.39"
    }
  }
}

locals {
  common_tags = concat(
    ["env:${var.env}", "project:${var.project}", "managed-by:terraform"],
    var.extra_tags,
  )

  page   = var.page_target
  notify = var.notify_target

  rds_storage_threshold_bytes = var.rds_free_storage_threshold_gb * 1024 * 1024 * 1024

  # --- The async pipelines. These are the product. ---
  # Every queue gets the same two monitors, because the same two things go wrong with all of
  # them: sends fail permanently and land in the dead-letter queue, or the consumer stops
  # keeping up and work goes stale. Both page. Neither produces a user-facing error, which
  # is exactly why they need alerts.
  queue_monitors = merge([
    for key, q in var.queues : {
      "${key}-dlq-not-empty" = {
        name     = "[${var.env}] ${q.label} sends are dead-lettering"
        type     = "metric alert"
        priority = 1
        target   = local.page
        critical = 0
        warning  = null
        query    = "sum(last_5m):sum:aws.sqs.approximate_number_of_messages_visible{queuename:${q.dlq_name}} > 0"
        body     = <<-EOT
          ${q.label} jobs have failed enough times to land in the dead-letter queue, so those
          patients are not being contacted. Usually the third-party SMS/email provider is
          erroring or a credential expired.

          Check the DLQ contents and the consumer logs, fix the cause, then redrive the queue.
        EOT
      }

      "${key}-backlog-age" = {
        name     = "[${var.env}] ${q.label} queue is falling behind"
        type     = "metric alert"
        priority = 1
        target   = local.page
        critical = q.max_age_seconds
        warning  = q.max_age_seconds / 2
        query    = "max(last_10m):max:aws.sqs.approximate_age_of_oldest_message{queuename:${q.queue_name}} > ${q.max_age_seconds}"
        body     = <<-EOT
          The oldest unprocessed ${q.label} message is older than ${q.max_age_seconds}s. This
          work is time-sensitive: late is close to not done at all.

          Check that the consuming service has running tasks and that the provider responds.
        EOT
      }
    }
  ]...)

  monitors = merge(local.queue_monitors, {
    # --- The booking path. Patients cannot book, clinics cannot work. ---
    "api-5xx-rate" = {
      name     = "[${var.env}] API is returning 5xx"
      type     = "query alert"
      priority = 1
      target   = local.page
      critical = var.api_error_rate_threshold
      warning  = var.api_error_rate_threshold / 2
      query    = "sum(last_5m):sum:aws.applicationelb.httpcode_target_5xx{loadbalancer:${var.load_balancer_name}}.as_count() / sum:aws.applicationelb.request_count{loadbalancer:${var.load_balancer_name}}.as_count() > ${var.api_error_rate_threshold}"
      body     = <<-EOT
        Requests are failing at the target above the error-rate threshold. Clinic staff and
        patient booking pages are both affected.

        Check the most recent deploy first; rollback is redeploying the previous image tag.
      EOT
    }

    "alb-no-healthy-targets" = {
      name     = "[${var.env}] Load balancer has no healthy targets"
      type     = "metric alert"
      priority = 1
      target   = local.page
      critical = 1
      warning  = null
      query    = "min(last_5m):min:aws.applicationelb.healthy_host_count{loadbalancer:${var.load_balancer_name}} < 1"
      body     = <<-EOT
        Every target behind the load balancer is failing its health check. The site is down.

        Check ECS service events for tasks that cannot start, and the target group health
        check path.
      EOT
    }

    "api-latency-p95" = {
      name     = "[${var.env}] API p95 latency is degraded"
      type     = "metric alert"
      priority = 3
      target   = local.notify
      critical = var.api_p95_latency_seconds
      warning  = var.api_p95_latency_seconds * 0.7
      query    = "avg(last_10m):avg:aws.applicationelb.target_response_time.p95{loadbalancer:${var.load_balancer_name}} > ${var.api_p95_latency_seconds}"
      body     = <<-EOT
        p95 response time is above target. Not an outage yet, but this is what the database
        ceiling looks like on the way up. Check RDS CPU and connection count.
      EOT
    }

    # --- The database. The known ceiling in this architecture. ---
    "rds-free-storage" = {
      name     = "[${var.env}] Database is running out of storage"
      type     = "metric alert"
      priority = 1
      target   = local.page
      critical = local.rds_storage_threshold_bytes
      warning  = local.rds_storage_threshold_bytes * 2
      query    = "min(last_15m):min:aws.rds.free_storage_space{dbinstanceidentifier:${var.db_instance_identifier}} < ${local.rds_storage_threshold_bytes}"
      body     = <<-EOT
        Free storage is below ${var.rds_free_storage_threshold_gb} GB. Storage autoscaling
        should have handled this, so if it is firing, autoscaling has hit its ceiling.

        A full disk takes the database offline. Raise max_allocated_storage now.
      EOT
    }

    "rds-cpu" = {
      name     = "[${var.env}] Database CPU is high"
      type     = "metric alert"
      priority = 3
      target   = local.notify
      critical = var.rds_cpu_threshold
      warning  = var.rds_cpu_threshold * 0.8
      query    = "avg(last_15m):avg:aws.rds.cpuutilization{dbinstanceidentifier:${var.db_instance_identifier}} > ${var.rds_cpu_threshold}"
      body     = <<-EOT
        Sustained high database CPU. This is the first signal for the read-replica
        investment in EVOLUTION.md. Check Performance Insights for the dominant query.
      EOT
    }

    "rds-connections" = {
      name     = "[${var.env}] Database connection count is climbing"
      type     = "metric alert"
      priority = 3
      target   = local.notify
      critical = var.rds_connection_threshold
      warning  = var.rds_connection_threshold * 0.8
      query    = "avg(last_15m):avg:aws.rds.database_connections{dbinstanceidentifier:${var.db_instance_identifier}} > ${var.rds_connection_threshold}"
      body     = <<-EOT
        Connections are approaching the instance limit. Every Fargate task holds a pool, so
        this scales with task count, not with traffic.

        This is the trigger for RDS Proxy or PgBouncer in EVOLUTION.md.
      EOT
    }

    "internal-alb-no-healthy-targets" = {
      name     = "[${var.env}] Internal load balancer has no healthy targets"
      type     = "metric alert"
      priority = 1
      target   = local.page
      critical = 1
      warning  = null
      query    = "min(last_5m):min:aws.applicationelb.healthy_host_count{loadbalancer:${var.internal_load_balancer_name}} < 1"
      body     = <<-EOT
        Nothing is answering behind the internal load balancer, so the api and admin
        services are both down. The patient and clinician sites will start failing as their
        calls to the api time out.

        Check ECS service events for tasks that cannot start.
      EOT
    }

    # --- The worker has no inbound traffic, so nothing else notices when it dies. ---
    "worker-not-running" = {
      name     = "[${var.env}] Reminder worker has no running tasks"
      type     = "metric alert"
      priority = 1
      target   = local.page
      critical = 1
      warning  = null
      query    = "min(last_10m):min:aws.ecs.service.running{servicename:${var.worker_service_name}} < 1"
      body     = <<-EOT
        The reminder worker is not running. Nothing is dispatching reminders, and no
        user-facing request will fail to tell you about it, which is exactly why this pages.
      EOT
    }
  })
}

resource "datadog_monitor" "this" {
  for_each = local.monitors

  name    = each.value.name
  type    = each.value.type
  query   = each.value.query
  message = "${trimspace(each.value.body)}\n\n${each.value.target}"
  tags    = concat(local.common_tags, ["monitor:${each.key}"])

  priority          = each.value.priority
  notify_no_data    = var.notify_no_data
  no_data_timeframe = var.notify_no_data ? var.no_data_timeframe_minutes : null
  renotify_interval = each.value.priority == 1 ? var.renotify_interval_minutes : null

  # Give a newly started task a chance to report before evaluating it, so a rolling deploy
  # does not page. Not so long that a real outage sits undetected.
  new_group_delay     = 60
  notify_audit        = false
  include_tags        = true
  require_full_window = false

  monitor_thresholds {
    critical = tostring(each.value.critical)
    warning  = each.value.warning == null ? null : tostring(each.value.warning)
  }
}

# One SLO, not a dashboard full of them. It turns "is the API healthy" into an error budget
# the team can spend on shipping, which is the number worth reviewing weekly.
resource "datadog_service_level_objective" "api_availability" {
  count = var.create_slo ? 1 : 0

  name        = "[${var.env}] Booking API availability"
  type        = "monitor"
  description = "Share of time the API is serving requests without an elevated 5xx rate."
  monitor_ids = [datadog_monitor.this["api-5xx-rate"].id]
  tags        = local.common_tags

  thresholds {
    timeframe = "30d"
    target    = var.slo_target
    warning   = var.slo_warning
  }
}

# Staging generates the same telemetry as prod and none of the urgency. A permanent
# downtime keeps the dashboards and alert history while guaranteeing staging never pages.
# Without it, the usual outcome is someone muting staging by deleting its monitors.
resource "datadog_downtime_schedule" "permanent" {
  count = var.permanent_downtime ? 1 : 0

  scope   = "env:${var.env}"
  message = "Permanent downtime: ${var.env} is a test environment and must never page. Monitors still evaluate and record history."

  monitor_identifier {
    monitor_tags = ["env:${var.env}"]
  }

  recurring_schedule {
    timezone = "UTC"
    recurrence {
      duration = "1d"
      rrule    = "FREQ=DAILY;INTERVAL=1"
    }
  }

  display_timezone                 = "UTC"
  notify_end_states                = []
  notify_end_types                 = []
  mute_first_recovery_notification = true
}
