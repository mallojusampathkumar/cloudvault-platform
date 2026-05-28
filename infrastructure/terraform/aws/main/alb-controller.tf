# ============================================
# AWS Load Balancer Controller - IRSA setup
# Creates IAM policy + role bound to the controller's
# Kubernetes service account via OIDC (IRSA)
# ============================================

# The IAM policy (loaded from the downloaded JSON file)
resource "aws_iam_policy" "alb_controller" {
  name        = "${local.name_prefix}-alb-controller-policy"
  description = "Permissions for AWS Load Balancer Controller"
  policy      = file("${path.module}/alb-iam-policy.json")
}

# Extract the OIDC provider URL without https:// prefix (needed for trust condition)
locals {
  oidc_provider_url = replace(aws_iam_openid_connect_provider.eks.url, "https://", "")
}

# IAM role the controller pod will assume
resource "aws_iam_role" "alb_controller" {
  name = "${local.name_prefix}-alb-controller-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          # Only THIS service account in THIS namespace can assume the role
          "${local.oidc_provider_url}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          "${local.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}

output "alb_controller_role_arn" {
  value       = aws_iam_role.alb_controller.arn
  description = "IAM role ARN for the AWS Load Balancer Controller service account"
}
