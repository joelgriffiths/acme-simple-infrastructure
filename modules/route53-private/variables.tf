variable "name" {
  description = "Name prefix, e.g. acme-prod"
  type        = string
}

variable "domain_name" {
  description = "Internal zone apex, e.g. dumbidea.internal"
  type        = string
}

variable "vpc_id" {
  description = "VPC the zone is associated with. Without this the names resolve nowhere."
  type        = string
}

variable "vpc_region" {
  description = "Region of that VPC"
  type        = string
}

variable "hostnames" {
  description = "Internal hostnames to alias at the internal load balancer"
  type        = list(string)
}

variable "alb_dns_name" {
  description = "Internal ALB DNS name"
  type        = string
}

variable "alb_zone_id" {
  description = "Internal ALB hosted zone ID"
  type        = string
}

variable "force_destroy" {
  description = "Allow destroying the zone with records still in it (staging only)"
  type        = bool
  default     = false
}
