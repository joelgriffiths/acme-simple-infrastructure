output "fqdns" {
  value = [for r in aws_route53_record.alias : r.fqdn]
}
