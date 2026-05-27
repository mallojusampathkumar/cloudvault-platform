# ============================================
# AWS Secrets Manager
# Stores DB credentials securely (not in code, not in tfvars)
# ============================================

# Random password for RDS - generated each apply
resource "random_password" "rds" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"  # Avoid chars RDS dislikes
}

resource "aws_secretsmanager_secret" "rds" {
  name                    = "${local.name_prefix}-rds-credentials"
  description             = "PostgreSQL credentials for CloudVault"
  recovery_window_in_days = 0  # Allow immediate delete (dev); use 7-30 in prod
}

resource "aws_secretsmanager_secret_version" "rds" {
  secret_id = aws_secretsmanager_secret.rds.id
  secret_string = jsonencode({
    username = "cloudvault_admin"
    password = random_password.rds.result
    engine   = "postgres"
    port     = 5432
  })
}
