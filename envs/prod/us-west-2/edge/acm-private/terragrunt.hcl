include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform { source = "${get_repo_root()}//modules/acm-private" }

locals {
  env    = include.root.locals.env
  region = include.root.locals.region
  app    = read_terragrunt_config("${get_terragrunt_dir()}/app_config.hcl").locals
}

# The internal domain does not exist publicly, so a public CA cannot validate it. This
# stands up our own root CA and issues the internal load balancer's certificate from it.
#
# COST: AWS Private CA bills per CA per month whether it issues anything or not. See the
# module header and ARCHITECTURE.md before applying.
#
# After the first apply, export the root certificate for the directory:
#   terragrunt output -raw ca_certificate_pem > acme-internal-root-ca.pem
inputs = {
  name           = local.env.project_prefix
  ca_common_name = "${local.app.ca_common_name} (${local.env.environment})"

  organization        = local.app.organization
  organizational_unit = local.app.organizational_unit
  country             = local.app.country
  ca_validity_years   = local.app.ca_validity_years

  usage_mode = local.env.private_ca_usage_mode

  domain_name               = local.region.internal_hosts[0]
  subject_alternative_names = slice(local.region.internal_hosts, 1, length(local.region.internal_hosts))
}
