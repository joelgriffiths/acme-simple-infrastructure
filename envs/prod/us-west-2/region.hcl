# Region-scoped values for prod/us-west-2: availability zones, address space, DNS.
# Sizing and environment identity live one level up in envs/prod/env.hcl.
locals {
  region = "us-west-2"
  azs    = ["us-west-2a", "us-west-2b"]

  vpc_cidr             = "10.30.0.0/16"
  public_subnet_cidrs  = ["10.30.0.0/24", "10.30.1.0/24"]
  private_subnet_cidrs = ["10.30.10.0/24", "10.30.11.0/24"]

  # --- DNS ---------------------------------------------------------------------------------
  # Two zones, because two of the four web services have no business being on the internet.
  #
  #   public_domain   internet-facing, ACM public certificate, WAF in front
  #   private_domain  a Route53 PRIVATE hosted zone associated with this VPC, so the name
  #                   resolves only from inside it. Certificates are issued by our own ACM PCA.
  #
  # Prod holds the apex names; staging uses its own subdomains rather than the same private
  # zone name in a second VPC. Two private zones with the same apex resolving to different
  # addresses depending on which VPC you are in is a debugging trap that costs more than the
  # tidiness is worth, and the accounts are separate now anyway.
  public_domain  = "dumbidea.us"
  private_domain = "dumbidea.internal"

  public_zone_id = "Z00000000000000000PRD" # placeholder public Route53 hosted zone

  # Role => hostname.
  #   api        internal only. Nothing outside the VPC calls it; the frontends reach it
  #              over the internal ALB.
  #   patient    public. Patients on the open internet.
  #   clinician  public. Clinic staff, who are not on our network.
  #   admin      internal only. The one cross-tenant application, reachable over the bastion
  #              (or a VPN, once there is one) and never from the internet.
  hosts = {
    api       = "api.${local.private_domain}"
    patient   = "book.${local.public_domain}"
    clinician = "clinic.${local.public_domain}"
    admin     = "admin.${local.private_domain}"
  }

  api_host       = local.hosts.api
  patient_host   = local.hosts.patient
  clinician_host = local.hosts.clinician
  admin_host     = local.hosts.admin

  # Which hostnames sit behind which load balancer. The WAF unit reads public_hosts and
  # fails if one of them has no rules, so a hostname cannot be made public without also
  # acquiring WAF rules.
  public_hosts   = [local.hosts.patient, local.hosts.clinician]
  internal_hosts = [local.hosts.api, local.hosts.admin]
}
