variable "name" {
  description = "Name prefix, e.g. acme-staging"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR, used to scope the bastion's Postgres egress"
  type        = string
}

variable "subnet_id" {
  description = "Public subnet for the bastion (it needs a routable address for SSH)"
  type        = string
}

variable "instance_type" {
  description = "Instance type. A bastion runs an SSH daemon and psql; nano is plenty."
  type        = string
  default     = "t4g.nano"
}

variable "ssh_public_keys" {
  description = "Public keys allowed to log in, from envs/<env>/env.hcl. Removing a line and applying revokes that person."
  type        = list(string)
}

variable "ingress_cidrs" {
  description = "CIDRs allowed to reach port 22. Must not be 0.0.0.0/0: use Session Manager instead of opening SSH to the internet."
  type        = list(string)

  validation {
    condition     = !contains(var.ingress_cidrs, "0.0.0.0/0")
    error_message = "Refusing to expose SSH to the whole internet. Scope ingress_cidrs to known ranges, or use SSM Session Manager with an empty list."
  }
}
