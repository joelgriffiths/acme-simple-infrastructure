include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform { source = "${get_repo_root()}//modules/acm" }

locals {
  region = include.root.locals.region
}

# Public, DNS-validated certificate for the internet-facing hostnames. Validation records
# are written into the public hosted zone, so this only works for names a CA can resolve.
inputs = {
  domain_name               = local.region.public_hosts[0]
  subject_alternative_names = slice(local.region.public_hosts, 1, length(local.region.public_hosts))
  zone_id                   = local.region.public_zone_id
}
