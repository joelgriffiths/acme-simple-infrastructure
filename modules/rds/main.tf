# Managed PostgreSQL on RDS. Encrypted at rest, in private subnets, reachable only from
# the ECS task security groups. Master credentials are managed by RDS in Secrets Manager
# (no password in state). Multi-AZ is a per-env toggle (on in prod).

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db"
  subnet_ids = var.subnet_ids
  tags       = { Name = "${var.name}-db" }
}

resource "aws_security_group" "db" {
  name        = "${var.name}-db"
  description = "Postgres access from ECS tasks only"
  vpc_id      = var.vpc_id

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-db" }
}

resource "aws_security_group_rule" "from_tasks" {
  count                    = length(var.allowed_security_group_ids)
  type                     = "ingress"
  security_group_id        = aws_security_group.db.id
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = var.allowed_security_group_ids[count.index]
  description              = "Postgres from an ECS task SG"
}

# CIDR-scoped ingress (the VPC's private range). Used instead of SG-to-SG when the ECS
# services must also read the DB endpoint, which would otherwise create a dependency cycle
# (rds -> task SGs -> rds outputs). Scoped to the VPC, where only our tasks run.
resource "aws_security_group_rule" "from_cidrs" {
  count             = length(var.allowed_cidr_blocks) > 0 ? 1 : 0
  type              = "ingress"
  security_group_id = aws_security_group.db.id
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  cidr_blocks       = var.allowed_cidr_blocks
  description       = "Postgres from the VPC private range"
}

resource "aws_db_instance" "this" {
  identifier     = "${var.name}-pg"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.username
  # RDS manages the master password in Secrets Manager — never in Terraform state.
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  multi_az               = var.multi_az

  backup_retention_period = var.backup_retention_period
  backup_window           = "07:00-08:00"
  maintenance_window      = "sun:08:00-sun:09:00"
  copy_tags_to_snapshot   = true

  performance_insights_enabled = var.performance_insights_enabled
  deletion_protection          = var.deletion_protection
  skip_final_snapshot          = var.skip_final_snapshot
  final_snapshot_identifier    = var.skip_final_snapshot ? null : "${var.name}-pg-final"
  auto_minor_version_upgrade   = true
  apply_immediately            = var.apply_immediately

  tags = { Name = "${var.name}-pg" }
}
