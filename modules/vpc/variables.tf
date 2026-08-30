variable "name" {
  description = "Name prefix for VPC resources (e.g. acme-staging)"
  type        = string
}

variable "cidr_block" {
  description = "VPC CIDR block"
  type        = string
}

variable "azs" {
  description = "Availability zones to spread subnets across"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs, one per AZ (ALB + NAT live here)"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs, one per AZ (ECS tasks + RDS live here)"
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "One NAT gateway for all AZs (cheaper) vs one per AZ (HA egress)"
  type        = bool
  default     = true
}
