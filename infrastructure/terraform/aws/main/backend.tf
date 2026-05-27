# Tells Terraform to store state in S3 (the bucket we created via bootstrap)
# and use DynamoDB for locking.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "cloudvault-tfstate-addf753d"
    key            = "main/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "cloudvault-tflock"
    encrypt        = true
  }
}
