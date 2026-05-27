# Provider configuration - separated from backend for clarity

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = "devops"
    }
  }
}

# Look up available AZs in this region (for safety/validation)
data "aws_availability_zones" "available" {
  state = "available"
}

# Get current AWS account ID and region for use in policies
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
