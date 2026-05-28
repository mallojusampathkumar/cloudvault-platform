# ============================================
# Extra ELB permissions for newer LB Controller versions
# The downloaded iam_policy.json (v2.7.2) lacks some
# permissions the installed controller (v3.x) needs.
# ============================================
resource "aws_iam_role_policy" "alb_controller_extra" {
  name = "alb-controller-extra-elb-perms"
  role = aws_iam_role.alb_controller.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "elasticloadbalancing:DescribeListenerAttributes",
        "elasticloadbalancing:ModifyListenerAttributes",
        "elasticloadbalancing:DescribeCapacityReservation",
        "elasticloadbalancing:ModifyCapacityReservation",
        "elasticloadbalancing:DescribeTrustStores"
      ]
      Resource = "*"
    }]
  })
}
