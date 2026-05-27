# Bootstrap: Creates the S3 bucket and DynamoDB table that will store
# Terraform state for ALL other Terraform configs.
# This config uses LOCAL state (chicken-and-egg problem).

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
  default_tags {
    tags = {
      Project     = "cloudvault"
      ManagedBy   = "terraform"
      Environment = "shared"
    }
  }
}

# Unique suffix to avoid bucket name collisions (S3 names are global)
resource "random_id" "suffix" {
  byte_length = 4
}

# S3 bucket to hold Terraform state files
resource "aws_s3_bucket" "tfstate" {
  bucket = "cloudvault-tfstate-${random_id.suffix.hex}"
}

# Block all public access (state files contain secrets!)
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning - if state gets corrupted, we can restore previous version
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Encrypt state at rest
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# DynamoDB table for state locking
# Prevents two engineers from running terraform apply at the same time
resource "aws_dynamodb_table" "tflock" {
  name         = "cloudvault-tflock"
  billing_mode = "PAY_PER_REQUEST"  # Cheap - only pays per lock op
  hash_key     = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }
}

output "state_bucket_name" {
  value       = aws_s3_bucket.tfstate.id
  description = "Use this as the bucket name in main/backend.tf"
}

output "lock_table_name" {
  value = aws_dynamodb_table.tflock.id
}
