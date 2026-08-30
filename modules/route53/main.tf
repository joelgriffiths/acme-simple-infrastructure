# Alias A records for the app hostnames, pointing at the ALB.
resource "aws_route53_record" "alias" {
  for_each = toset(var.hostnames)
  zone_id  = var.zone_id
  name     = each.value
  type     = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}
