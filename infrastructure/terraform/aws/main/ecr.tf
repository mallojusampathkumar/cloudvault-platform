# ============================================
# ECR (Elastic Container Registry)
# Private Docker registries - one per microservice
# ============================================

locals {
  services = [
    "user-service",
    "product-service",
    "cart-service",
    "order-service",
    "payment-service",
    "notification-service",
    "frontend",
  ]
}

resource "aws_ecr_repository" "services" {
  for_each = toset(local.services)

  name                 = "${var.project_name}/${each.value}"
  image_tag_mutability = "MUTABLE"

  # IMPORTANT:
  # Allows Terraform destroy to remove repo even if images exist
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name = "${var.project_name}-${each.value}"
  }
}

# Lifecycle policy - keep only last 10 images
resource "aws_ecr_lifecycle_policy" "services" {
  for_each   = aws_ecr_repository.services
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only last 10 images"

        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }

        action = {
          type = "expire"
        }
      }
    ]
  })
}
