# ============================================
# VPC + Networking
# ============================================
# Architecture:
#  - 1 VPC (10.20.0.0/16)
#  - 2 public subnets (one per AZ) for load balancers, NAT
#  - 2 private subnets (one per AZ) for EKS nodes, RDS
#  - 1 Internet Gateway (public subnets reach internet)
#  - 1 NAT Gateway (private subnets reach internet outbound only)
#  - Route tables wired up correctly

# Local values - computed once, reused everywhere
locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ============================================
# The VPC itself
# ============================================
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true  # Required for EKS

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

# ============================================
# Internet Gateway - VPC's connection to the internet
# ============================================
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

# ============================================
# Public Subnets - for load balancers and NAT
# ============================================
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true  # Instances here get public IPs

  tags = {
    Name                                        = "${local.name_prefix}-public-${var.azs[count.index]}"
    "kubernetes.io/role/elb"                    = "1"   # Tells EKS: put public LBs here
    "kubernetes.io/cluster/${local.name_prefix}-eks" = "shared"
  }
}

# ============================================
# Private Subnets - for EKS nodes, RDS, internal workloads
# ============================================
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name                                        = "${local.name_prefix}-private-${var.azs[count.index]}"
    "kubernetes.io/role/internal-elb"           = "1"   # Internal LBs here
    "kubernetes.io/cluster/${local.name_prefix}-eks" = "shared"
  }
}

# ============================================
# Elastic IP for NAT Gateway
# ============================================
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}-nat-eip"
  }

  depends_on = [aws_internet_gateway.main]
}

# ============================================
# NAT Gateway - lets private subnets reach internet OUTBOUND
# Cost note: ~$0.045/hr + data transfer. We use ONE NAT (cost optimization)
# instead of one per AZ. Production HA setups use one NAT per AZ.
# ============================================
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id  # Place in first public subnet

  tags = {
    Name = "${local.name_prefix}-nat"
  }

  depends_on = [aws_internet_gateway.main]
}

# ============================================
# Route Tables
# ============================================
# Public route table: route 0.0.0.0/0 to Internet Gateway
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${local.name_prefix}-rt-public"
  }
}

# Private route table: route 0.0.0.0/0 to NAT Gateway
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${local.name_prefix}-rt-private"
  }
}

# Associate public subnets with public route table
resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Associate private subnets with private route table
resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
