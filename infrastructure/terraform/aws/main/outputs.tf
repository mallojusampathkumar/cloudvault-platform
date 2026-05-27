# ============================================
# Outputs - important values for use elsewhere
# ============================================

output "vpc_id" {
  value       = aws_vpc.main.id
  description = "The VPC ID"
}

output "eks_cluster_name" {
  value       = aws_eks_cluster.main.name
  description = "EKS cluster name (use with aws eks update-kubeconfig)"
}

output "eks_cluster_endpoint" {
  value       = aws_eks_cluster.main.endpoint
  description = "EKS API server endpoint"
}

output "eks_oidc_provider_arn" {
  value       = aws_iam_openid_connect_provider.eks.arn
  description = "OIDC provider ARN (for IRSA setup later)"
}

output "ecr_registry_url" {
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
  description = "ECR registry URL prefix"
}

output "ecr_repository_urls" {
  value       = { for k, v in aws_ecr_repository.services : k => v.repository_url }
  description = "Map of service name to ECR repository URL"
}

output "rds_endpoint" {
  value       = aws_db_instance.main.endpoint
  description = "RDS PostgreSQL endpoint (hostname:port)"
}

output "rds_secret_arn" {
  value       = aws_secretsmanager_secret.rds.arn
  description = "ARN of the RDS credentials secret"
}
