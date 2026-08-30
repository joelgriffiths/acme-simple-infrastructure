# Repo-wide configuration. Everything here is either global or a per-environment identity
# value. Nothing that varies by region and nothing a single component owns belongs here.
#
# Layering (see CLAUDE.md):
#   config.hcl                       -> this file: accounts, project name, state backends
#   envs/<env>/env.hcl               -> environment identity + sizing
#   envs/<env>/<region>/region.hcl   -> AZs, CIDRs, DNS
#   <unit>/app_config.hcl            -> values only that one component cares about
locals {
  project = "acme"

  # One AWS account per environment. Placeholder IDs, but deliberately DIFFERENT ones:
  # sharing an account between staging and prod would make allowed_account_ids in the
  # generated provider a no-op, and would put both environments' Terraform state and lock
  # tables in the same blast radius. Everything else in the repo is name-prefixed per
  # environment, so those two were the real collisions.
  accounts = {
    staging = {
      account_id  = "491803677147"
      aws_profile = "acme-staging"
    }
    prod = {
      account_id  = "730925632418"
      aws_profile = "acme-prod"
    }
  }

  # Terraform state lives in the SAME account as the resources it describes, one bucket and
  # one lock table per environment, created by envs/bootstrap/<env>. Centralising state in a
  # shared tools account would mean anyone with access there could corrupt or destroy prod's
  # state, which defeats the account boundary. Shared *infrastructure* (registries, Atlantis,
  # dashboards) is a good fit for a tools account; state is not shared, it is per-environment.
  state_buckets = {
    for env, acct in local.accounts :
    env => "${local.project}-${env}-tfstate-${acct.account_id}"
  }

  lock_tables = {
    for env, acct in local.accounts :
    env => "${local.project}-${env}-tf-locks"
  }

  # Per-environment KMS alias used by SOPS to encrypt envs/<env>/secrets/*.enc.yaml and to
  # encrypt SSM SecureStrings. Keys are created per environment and never shared.
  sops_kms_aliases = {
    for env, acct in local.accounts :
    env => "arn:aws:kms:us-west-2:${acct.account_id}:alias/${local.project}-${env}-secrets"
  }
}
