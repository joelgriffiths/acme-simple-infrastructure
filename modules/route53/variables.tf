variable "zone_id" { type = string }
variable "hostnames" {
  description = "FQDNs to alias to the ALB (e.g. api./app./book.)"
  type        = list(string)
}
variable "alb_dns_name" { type = string }
variable "alb_zone_id" { type = string }
