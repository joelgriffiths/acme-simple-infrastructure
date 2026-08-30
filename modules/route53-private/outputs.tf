output "zone_id" {
  description = "Private hosted zone ID"
  value       = aws_route53_zone.internal.zone_id
}

output "name_servers" {
  description = "Zone name servers (informational; a private zone is served by the VPC resolver)"
  value       = aws_route53_zone.internal.name_servers
}
