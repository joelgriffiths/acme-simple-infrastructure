# A private hosted zone for the internal domain, associated with this VPC.
#
# Association with the VPC is what makes the names resolve: without it the zone exists and
# answers nobody. The VPC also needs DNS support and DNS hostnames enabled, which the vpc
# module sets.
#
# Nothing outside an associated VPC can resolve these names, which is the point. The bastion
# sits inside the VPC, so tunnelling through it is enough to reach the internal hostnames
# from a laptop.

resource "aws_route53_zone" "internal" {
  name          = var.domain_name
  comment       = "Internal-only names for ${var.name}. Resolves inside the associated VPCs only."
  force_destroy = var.force_destroy

  vpc {
    vpc_id     = var.vpc_id
    vpc_region = var.vpc_region
  }

  tags = { Name = var.domain_name }

  lifecycle {
    # Additional VPC associations (a peered tools VPC, for example) are made outside this
    # module with aws_route53_zone_association; do not fight them.
    ignore_changes = [vpc]
  }
}

resource "aws_route53_record" "alias" {
  for_each = toset(var.hostnames)

  zone_id = aws_route53_zone.internal.zone_id
  name    = each.value
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}
