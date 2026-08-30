# AWS WAF in front of the ALB.
#
# Attached to the internet-facing load balancer only. The internal ALB carries api. and
# admin. on a private hosted zone with no public address, so there is nothing for a WAF to
# filter there and no reason to pay for one.
#
# IMPORTANT SHAPE NOTE: WAF associates one Web ACL with one load balancer, not one per
# listener rule or hostname. Both external hostnames share one ALB, so the per-hostname
# tuning happens *inside* one Web ACL using scope-down statements on the Host header. Each
# hostname gets its own managed rule groups and its own rate limits, and they can be moved
# from count to block independently.
#
# Every rule starts in count mode by default. Turning on a managed rule set in block mode
# against a live booking flow is how you take the site down at 2am with no deploy to blame.
# Watch the counts for a week, then flip count_only to false per hostname.

locals {
  hosts = keys(var.host_rules)

  # One rule per (hostname, managed rule group). Priorities are assigned from a stable
  # ordering so adding a hostname does not renumber the existing rules.
  managed_rules = flatten([
    for host_index, host in local.hosts : [
      for group_index, group in lookup(var.host_rules[host], "managed_rule_groups", []) : {
        key        = "${host}-${group}"
        host       = host
        group      = group
        count_only = lookup(var.host_rules[host], "count_only", true)
        priority   = (host_index * 100) + group_index + 1
      }
    ]
  ])

  # A tighter rate limit on the authentication paths only.
  #
  # A blanket per-host limit is not an anti-credential-stuffing control: 1,500 requests per
  # five minutes is still 1,500 password guesses. Scoping a much lower limit to the login
  # paths is what actually costs an attacker something, and it cannot lock a clinic out of
  # the rest of the app when it fires.
  login_rules = [
    for host_index, host in local.hosts : {
      key        = "${host}-login-rate"
      host       = host
      limit      = var.host_rules[host].login_rate_limit
      regex      = "^(${join("|", lookup(var.host_rules[host], "login_path_prefixes", []))})"
      count_only = lookup(var.host_rules[host], "count_only", true)
      priority   = (host_index * 100) + 60
    }
    if lookup(var.host_rules[host], "login_rate_limit", null) != null
    && length(lookup(var.host_rules[host], "login_path_prefixes", [])) > 0
  ]

  rate_rules = [
    for host_index, host in local.hosts : {
      key        = "${host}-rate"
      host       = host
      limit      = var.host_rules[host].rate_limit
      count_only = lookup(var.host_rules[host], "count_only", true)
      priority   = (host_index * 100) + 50
    } if lookup(var.host_rules[host], "rate_limit", null) != null
  ]
}

resource "aws_wafv2_web_acl" "this" {
  name        = "${var.name}-waf"
  description = "Per-hostname WAF for ${var.name}"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # --- Managed rule groups, scoped to one hostname each ---
  dynamic "rule" {
    for_each = { for r in local.managed_rules : r.key => r }
    content {
      name     = replace(rule.value.key, ".", "-")
      priority = rule.value.priority

      override_action {
        dynamic "count" {
          for_each = rule.value.count_only ? [1] : []
          content {}
        }
        dynamic "none" {
          for_each = rule.value.count_only ? [] : [1]
          content {}
        }
      }

      statement {
        managed_rule_group_statement {
          name        = rule.value.group
          vendor_name = "AWS"

          scope_down_statement {
            byte_match_statement {
              field_to_match {
                single_header { name = "host" }
              }
              positional_constraint = "EXACTLY"
              search_string         = rule.value.host
              text_transformation {
                priority = 0
                type     = "LOWERCASE"
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = replace(rule.value.key, ".", "-")
        sampled_requests_enabled   = true
      }
    }
  }

  # --- Per-hostname rate limiting ---
  # The booking pages and the clinic app have very different traffic shapes: a clinic
  # opening its schedule looks nothing like a patient clicking a reminder link, and the
  # login endpoint is the one that attracts credential stuffing.
  dynamic "rule" {
    for_each = { for r in local.rate_rules : r.key => r }
    content {
      name     = replace(rule.value.key, ".", "-")
      priority = rule.value.priority

      action {
        dynamic "count" {
          for_each = rule.value.count_only ? [1] : []
          content {}
        }
        dynamic "block" {
          for_each = rule.value.count_only ? [] : [1]
          content {}
        }
      }

      statement {
        rate_based_statement {
          limit              = rule.value.limit
          aggregate_key_type = "IP"

          scope_down_statement {
            byte_match_statement {
              field_to_match {
                single_header { name = "host" }
              }
              positional_constraint = "EXACTLY"
              search_string         = rule.value.host
              text_transformation {
                priority = 0
                type     = "LOWERCASE"
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = replace(rule.value.key, ".", "-")
        sampled_requests_enabled   = true
      }
    }
  }

  # --- Authentication-path rate limiting ---
  dynamic "rule" {
    for_each = { for r in local.login_rules : r.key => r }
    content {
      name     = replace(rule.value.key, ".", "-")
      priority = rule.value.priority

      action {
        dynamic "count" {
          for_each = rule.value.count_only ? [1] : []
          content {}
        }
        dynamic "block" {
          for_each = rule.value.count_only ? [] : [1]
          content {}
        }
      }

      statement {
        rate_based_statement {
          limit              = rule.value.limit
          aggregate_key_type = "IP"

          scope_down_statement {
            and_statement {
              statement {
                byte_match_statement {
                  field_to_match {
                    single_header { name = "host" }
                  }
                  positional_constraint = "EXACTLY"
                  search_string         = rule.value.host
                  text_transformation {
                    priority = 0
                    type     = "LOWERCASE"
                  }
                }
              }

              statement {
                regex_match_statement {
                  regex_string = rule.value.regex
                  field_to_match {
                    uri_path {}
                  }
                  text_transformation {
                    priority = 0
                    type     = "LOWERCASE"
                  }
                }
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = replace(rule.value.key, ".", "-")
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name}-waf"
    sampled_requests_enabled   = true
  }

  tags = { Name = "${var.name}-waf" }
}

resource "aws_wafv2_web_acl_association" "this" {
  resource_arn = var.alb_arn
  web_acl_arn  = aws_wafv2_web_acl.this.arn
}

# WAF logs are how you tune the rules: they show what each rule *would* have blocked while
# it is still in count mode. The log group name must start with aws-waf-logs-.
resource "aws_cloudwatch_log_group" "waf" {
  count             = var.enable_logging ? 1 : 0
  name              = "aws-waf-logs-${var.name}"
  retention_in_days = var.log_retention_days
  tags              = { Name = "aws-waf-logs-${var.name}" }
}

resource "aws_wafv2_web_acl_logging_configuration" "this" {
  count                   = var.enable_logging ? 1 : 0
  resource_arn            = aws_wafv2_web_acl.this.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf[0].arn]

  # Patient data must not land in WAF logs either. Authorization headers and the query
  # string are the two places it would show up.
  redacted_fields {
    single_header { name = "authorization" }
  }
  redacted_fields {
    single_header { name = "cookie" }
  }
  redacted_fields {
    query_string {}
  }
}
