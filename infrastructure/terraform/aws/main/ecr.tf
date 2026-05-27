# ============================================
# ECR (Elastic Container Registry)
# Private Docker registries - one per microservice
# This is where CI/CD will push images on Day 5
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
  image_tag_mutability = "MUTABLE"  # Allow overwriting tags (use IMMUTABLE in prod)

  image_scanning_configuration {
    scan_on_push = true  # Auto-scan for vulnerabilities on push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name = "${var.project_name}-${each.value}"
  }
}

# Lifecycle policy - delete old images to control costs
# Without this, ECR fills up with every build forever
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
