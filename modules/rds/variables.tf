variable "name" {
  description = "Name prefix (e.g. acme-staging)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets for the DB subnet group"
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "ECS task SGs allowed to connect on 5432 (SG-to-SG; use when no dep cycle)"
  type        = list(string)
  default     = []
}

variable "allowed_cidr_blocks" {
  description = "CIDRs allowed on 5432 (e.g. the VPC private range) to avoid a dependency cycle"
  type        = list(string)
  default     = []
}

variable "engine_version" {
  description = "PostgreSQL major/minor version"
  type        = string
  default     = "16.4"
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "Initial storage (GiB)"
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Storage autoscaling ceiling (GiB)"
  type        = number
  default     = 100
}

variable "db_name" {
  description = "Initial database name"
  type        = string
  default     = "acme"
}

variable "username" {
  description = "Master username"
  type        = string
  default     = "acme_admin"
}

variable "multi_az" {
  description = "Multi-AZ failover instance (enable in prod)"
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Automated backup retention (days)"
  type        = number
  default     = 7
}

variable "performance_insights_enabled" {
  description = "Enable Performance Insights"
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Prevent accidental deletion (enable in prod)"
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot on destroy (true in staging, false in prod)"
  type        = bool
  default     = true
}

variable "apply_immediately" {
  description = "Apply changes immediately vs next maintenance window"
  type        = bool
  default     = false
}
