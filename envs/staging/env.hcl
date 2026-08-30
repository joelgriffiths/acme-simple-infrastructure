# Staging environment: identity + sizing. Deliberately small.
#
# This file and envs/<env>/<region>/region.hcl are the ONLY places an environment-specific
# value may live. terragrunt.hcl files are copied verbatim between environments by the
# promotion pipeline, so anything that differs between staging and prod belongs here.
locals {
  config = read_terragrunt_config("${get_repo_root()}/config.hcl").locals

  environment    = "staging"
  account_id     = local.config.accounts["staging"].account_id
  aws_profile    = local.config.accounts["staging"].aws_profile
  project_prefix = "${local.config.project}-staging"

  # SSM namespace for this environment's application parameters.
  ssm_prefix     = "/${local.config.project}/staging"
  sops_kms_alias = local.config.sops_kms_aliases["staging"]

  # Terraform state for this environment, in this environment's own account.
  state_bucket = local.config.state_buckets["staging"]
  lock_table   = local.config.lock_tables["staging"]

  # --- Networking / edge ---
  single_nat_gateway       = true
  alb_ingress_cidrs        = ["0.0.0.0/0"]
  alb_deletion_protection  = false
  alb_access_log_retention = 90

  # --- Private CA ---
  # AWS Private CA bills per CA per month whether it issues anything or not: roughly $400
  # in GENERAL_PURPOSE, roughly $50 in SHORT_LIVED_CERTIFICATE (7-day certs). Staging runs
  # short-lived to keep the standing cost down; if weekly rotation causes trouble here, it
  # would have caused it in prod too, so this is the right place to find out.
  private_ca_usage_mode = "SHORT_LIVED_CERTIFICATE"

  # --- Logging ---
  log_retention_days = 14

  # --- Registry ---
  # Staging may need its registry torn down and rebuilt; prod must never be destroyable
  # with images still in it.
  ecr_force_delete = true

  # --- Data ---
  rds = {
    instance_class          = "db.t4g.micro"
    allocated_storage       = 20
    multi_az                = false
    backup_retention_period = 7
    deletion_protection     = false
    skip_final_snapshot     = true
    performance_insights    = false
  }

  # --- Application behaviour ---
  provider_mode = "stub"

  # --- Compute ---
  api = {
    cpu                = 512, memory = 1024, desired_count = 1
    enable_autoscaling = false, min_count = 1, max_count = 2
  }
  patient = {
    cpu                = 256, memory = 512, desired_count = 1
    enable_autoscaling = false, min_count = 1, max_count = 2
  }
  clinician = {
    cpu                = 256, memory = 512, desired_count = 1
    enable_autoscaling = false, min_count = 1, max_count = 2
  }
  admin = {
    cpu                = 256, memory = 512, desired_count = 1
    enable_autoscaling = false, min_count = 1, max_count = 2
  }
  worker = {
    cpu = 256, memory = 512, desired_count = 1
  }
  rebooking = {
    cpu = 256, memory = 512, desired_count = 1
  }
  scheduler = {
    cpu = 256, memory = 512, desired_count = 1
  }


  # --- Bastion ---
  # Interim answer for engineer access to the database, which lives in a private subnet.
  # Tailscale or a VPN is the better long-term shape; see EVOLUTION.md.
  #
  # Access is by public key, listed here. Adding someone is a PR; removing someone is
  # deleting a line and applying. There is no shared key and no key passed around by hand.
  bastion = {
    enabled       = true
    instance_type = "t4g.nano"

    # MUST NOT be 0.0.0.0/0 (the module refuses it). Replace with the office or VPN range.
    # For an engineer with no fixed address, use SSM Session Manager instead of widening
    # this: the instance profile already allows it and it opens no port at all.
    ingress_cidrs = ["203.0.113.0/24"]

    ssh_public_keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCqAVspJALPkYsjEy66t/66qMKjqvkuGUZe6D40kfXJXoTVyfagVwMRFwoNm1FZd+RjcbdePdUQE7Ap/J9JzCzL8lYU2m8sx9x8Nt3OxcQspo0UgDSuYzY2xPqvF4mFC7yeyp3QJ//WdOzwD/LqLCPIWZ3pF2I/VlhxHp2Lv5bgeyGY9TWzxFtqkL2KzA1HdAcmrEL3uX67YernTUWVY4x9ykUDqtaV3VAkOxu7Ya2Z6oF83MYL8msABWKKNz3kXDMe0mCRf/FMLJhsq2/WyBmgMvc4ymtGDkHyXVU0VR12xTkTJYxO11o3CVxcIuGyVvzc4KRCBg59E1bHdHct5rOd jgriffiths@cynical",
    ]
  }

  # --- WAF ---
  # Attached to the internet-facing ALB only; the internal ALB has no public address.
  # One Web ACL covers it, with per-hostname tuning inside via Host header scope-down
  # statements, keyed by role here and mapped to hostnames in region.hcl.
  #
  # Limits are per IP over a rolling 5-minute window.
  #
  # count_only = true logs what a rule WOULD block without blocking it. Leave it true for a
  # week, read the WAF logs, then flip per hostname. Going straight to block on a live
  # booking flow is how you take the site down with no deploy to blame.
  waf = {
    enabled            = true
    log_retention_days = 14

    rules = {
      # book.* -- patient booking. Unauthenticated, reached by SMS link, so a whole mobile
      # carrier NAT can legitimately appear as one IP. Sized to allow roughly 90-180
      # concurrent booking sessions from a single address before anything trips.
      patient = {
        rate_limit          = 6000
        managed_rule_groups = ["AWSManagedRulesCommonRuleSet", "AWSManagedRulesKnownBadInputsRuleSet"]
        count_only          = true
      }

      # clinic.* -- clinic staff login. A whole clinic shares one office IP, so the blanket
      # limit has to fit a busy front desk, which makes it useless against credential
      # stuffing on its own. The tight login limit is the control that actually bites, and
      # tripping it cannot lock a clinic out of the rest of the app.
      clinician = {
        rate_limit          = 4500
        managed_rule_groups = ["AWSManagedRulesCommonRuleSet", "AWSManagedRulesKnownBadInputsRuleSet", "AWSManagedRulesAmazonIpReputationList"]
        count_only          = true

        # 75/min per IP. WAF counts over a rolling 5-minute window, so 75 x 5.
        login_rate_limit    = 375
        login_path_prefixes = ["/login", "/signin", "/api/auth"]
      }
    }
  }

  # --- Monitoring ---
  # Staging sits under a permanent Datadog downtime: we want the dashboards and the data,
  # we do not want staging waking anyone up. Monitors still evaluate and record history,
  # which is what makes them trustworthy by the time they matter in prod.
  datadog = {
    enabled            = true
    site               = "datadoghq.com"
    env_tag            = "staging"
    permanent_downtime = true
    create_slo         = false
    notify_no_data     = false
    page_target        = "@slack-acme-eng"
    notify_target      = "@slack-acme-eng"
    apm_enabled        = false
    log_router_tag     = "bootstrap"

    # Issued by Datadog when the AWS integration is created. Not a credential, but it is
    # what stops another Datadog customer assuming our role, so it is per-environment.
    aws_integration_external_id = "REPLACE-with-the-external-id-datadog-issues"
  }
}
