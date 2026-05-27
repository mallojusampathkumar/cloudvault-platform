# ============================================
# RDS PostgreSQL Database
# - Lives in PRIVATE subnets (no public access)
# - Single-AZ for dev cost savings (Multi-AZ in prod)
# - Credentials pulled from Secrets Manager (not hardcoded)
# ============================================

# DB Subnet Group - tells RDS which subnets it can place itself in
resource "aws_db_subnet_group" "main" {
  name        = "${local.name_prefix}-db-subnet-group"
  description = "Subnet group for CloudVault RDS"
  subnet_ids  = aws_subnet.private[*].id  # Private subnets only

  tags = {
    Name = "${local.name_prefix}-db-subnet-group"
  }
}

# Parameter group - lets us tune PostgreSQL behavior
resource "aws_db_parameter_group" "main" {
  name        = "${local.name_prefix}-pg16"
  family      = "postgres16"
  description = "Custom params for CloudVault"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  # Slow query logging - log queries > 1000ms
  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }
}

# Decode the secret we generated earlier
locals {
  rds_creds = jsondecode(aws_secretsmanager_secret_version.rds.secret_string)
}

# The RDS PostgreSQL instance
resource "aws_db_instance" "main" {
  identifier = "${local.name_prefix}-postgres"

  engine               = "postgres"
  engine_version       = "16.14"
  instance_class       = "db.t3.micro"  # Cheapest, free-tier eligible
  allocated_storage    = 20             # GB
  max_allocated_storage = 100           # GB - auto-scale up to this
  storage_type         = "gp3"
  storage_encrypted    = true

  db_name  = "cloudvault"
  username = local.rds_creds.username
  password = local.rds_creds.password
  port     = 5432

  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.main.name
  parameter_group_name   = aws_db_parameter_group.main.name

  publicly_accessible = false   # NEVER expose RDS to internet
  multi_az            = false   # Dev cost optimization; prod = true

  # Backup configuration
  backup_retention_period = 7
  backup_window           = "03:00-04:00"  # UTC - low traffic time for Mumbai
  maintenance_window      = "Sun:04:00-Sun:05:00"

  # Critical for dev: allow easier teardown
  skip_final_snapshot = true   # Dev only! Set to false in prod
  deletion_protection = false  # Dev only! Set to true in prod

  # Performance Insights - free for 7 days retention
  performance_insights_enabled          = true
  performance_insights_retention_period = 7

  # CloudWatch log exports
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  tags = {
    Name = "${local.name_prefix}-postgres"
  }
}
