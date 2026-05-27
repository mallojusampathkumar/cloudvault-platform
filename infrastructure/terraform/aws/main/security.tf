# ============================================
# Security Groups
# Firewalls at the resource level
# ============================================

# === Security Group for EKS cluster control plane ===
resource "aws_security_group" "eks_cluster" {
  name        = "${local.name_prefix}-eks-cluster-sg"
  description = "EKS cluster control plane communication"
  vpc_id      = aws_vpc.main.id

  # Allow all outbound (so cluster can call AWS APIs)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-eks-cluster-sg"
  }
}

# === Security Group for EKS worker nodes ===
resource "aws_security_group" "eks_nodes" {
  name        = "${local.name_prefix}-eks-nodes-sg"
  description = "EKS worker nodes"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name                                            = "${local.name_prefix}-eks-nodes-sg"
    "kubernetes.io/cluster/${local.name_prefix}-eks" = "owned"
  }
}

# Nodes can talk to each other (pod-to-pod across nodes)
resource "aws_security_group_rule" "nodes_internal" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  source_security_group_id = aws_security_group.eks_nodes.id
  security_group_id        = aws_security_group.eks_nodes.id
  description              = "Allow nodes to communicate with each other"
}

# Control plane can talk to nodes (kubelet API, exec/logs/portforward)
resource "aws_security_group_rule" "nodes_from_cluster" {
  type                     = "ingress"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_cluster.id
  security_group_id        = aws_security_group.eks_nodes.id
  description              = "Allow cluster control plane to reach nodes"
}

# === Security Group for RDS PostgreSQL ===
resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "RDS PostgreSQL access"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-rds-sg"
  }
}

# Only EKS nodes can reach the database (least privilege)
resource "aws_security_group_rule" "rds_from_nodes" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_nodes.id
  security_group_id        = aws_security_group.rds.id
  description              = "Allow EKS nodes to reach PostgreSQL"
}

# ============================================
# Fix: Allow RDS access from EKS auto-created cluster SG
# EKS auto-creates an "eks-cluster-sg-<cluster-name>" SG on cluster creation
# and attaches it to all nodes - we need to allow that one too.
# ============================================
resource "aws_security_group_rule" "rds_from_eks_cluster_sg" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  security_group_id        = aws_security_group.rds.id
  description              = "Allow EKS auto-created cluster SG to reach PostgreSQL"
}
