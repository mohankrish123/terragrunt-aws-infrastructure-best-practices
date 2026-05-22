data "aws_vpc" "main" {
  filter {
    name   = "tag:Name"
    values = ["${var.application}-${var.environment}-vpc"]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
  filter {
    name   = "tag:Tier"
    values = ["private"]
  }
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.application}-${var.environment}"
  subnet_ids = data.aws_subnets.private.ids

  tags = {
    Name = "${var.application}-${var.environment}-db-subnet-group"
  }
}

resource "aws_security_group" "db" {
  name        = "${var.application}-${var.environment}-db"
  description = "Security group for RDS instance"
  vpc_id      = data.aws_vpc.main.id

  tags = {
    Name = "${var.application}-${var.environment}-db-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "db_postgres" {
  security_group_id = aws_security_group.db.id
  description       = "PostgreSQL from VPC"
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
  cidr_ipv4         = data.aws_vpc.main.cidr_block
}

resource "aws_db_parameter_group" "main" {
  name   = "${var.application}-${var.environment}-postgres17"
  family = "postgres17"

  dynamic "parameter" {
    for_each = var.db_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = lookup(parameter.value, "apply_method", "immediate")
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "main" {
  identifier = "${var.application}-${var.environment}"

  engine         = var.db_engine
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage = var.db_allocated_storage
  storage_type      = var.db_storage_type
  storage_encrypted = true

  db_name                     = replace("${var.application}_${var.environment}", "-", "_")
  username                    = var.application
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  parameter_group_name   = aws_db_parameter_group.main.name
  multi_az               = var.enable_multi_az
  publicly_accessible    = false

  backup_retention_period = var.db_backup_retention_period
  backup_window           = var.db_backup_window
  maintenance_window      = var.db_maintenance_window

  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.application}-${var.environment}-final"

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  tags = {
    Name = "${var.application}-${var.environment}-db"
  }
}
