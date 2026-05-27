# ============================================
# EKS Cluster + Managed Node Group
# This creates:
#  - The EKS control plane (managed by AWS)
#  - A managed node group (auto-managed EC2 instances)
#  - OIDC provider for IRSA (IAM Roles for Service Accounts)
# ============================================

# ============================================
# The EKS Cluster (control plane)
# ============================================
resource "aws_eks_cluster" "main" {
  name     = "${local.name_prefix}-eks"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.eks_cluster_version

  vpc_config {
    # Cluster API server endpoint lives in these subnets
    subnet_ids = concat(
      aws_subnet.public[*].id,
      aws_subnet.private[*].id
    )

    # Security group attached to the control plane ENIs
    security_group_ids = [aws_security_group.eks_cluster.id]

    # Public endpoint enabled so kubectl from your laptop can reach it
    # Private endpoint also enabled so nodes can reach control plane internally
    endpoint_public_access  = true
    endpoint_private_access = true

    # In production, restrict to your office/VPN CIDRs - this is wide open for learning
    public_access_cidrs = ["0.0.0.0/0"]
  }

  # Enable control plane logging - critical for debugging and audit
  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  # Encrypt secrets stored in etcd using KMS - production best practice
  # (Using default AWS-managed key here; production uses customer-managed KMS)

  # Wait for the IAM role policies before creating cluster
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
  ]

  tags = {
    Name = "${local.name_prefix}-eks"
  }
}

# ============================================
# OIDC Provider - enables IRSA (IAM Roles for Service Accounts)
# Lets pods assume IAM roles via service account tokens
# Critical for secure pod-to-AWS communication
# ============================================
data "tls_certificate" "eks_oidc" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

# ============================================
# Managed Node Group
# AWS handles AMI updates, scaling, replacements
# ============================================
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.name_prefix}-nodes"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = aws_subnet.private[*].id  # Nodes in PRIVATE subnets only

  instance_types = [var.eks_node_instance_type]
  capacity_type  = "ON_DEMAND"  # Use SPOT for ~70% cost savings in dev
  disk_size      = 30           # GB - default 20 fills up fast with images

  scaling_config {
    desired_size = var.eks_node_desired_size
    min_size     = var.eks_node_min_size
    max_size     = var.eks_node_max_size
  }

  update_config {
    max_unavailable = 1  # Roll one node at a time during updates
  }

  # Labels applied to all nodes in this group
  labels = {
    role        = "worker"
    environment = var.environment
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_ecr_readonly,
  ]

  tags = {
    Name = "${local.name_prefix}-node-group"
  }

  lifecycle {
    # Prevent recreation if AWS changes the AMI version automatically
    ignore_changes = [scaling_config[0].desired_size]
  }
}
