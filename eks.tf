resource "aws_eks_cluster" "main" {
  name = "${var.project}-eks"
  # Upgrade preparation: replace the fixed "1.34" with an independent target.
  # Keep the baseline unchanged; the first upgrade target will be 1.35, not 1.36.
  version  = var.eks_cluster_version
  role_arn = aws_iam_role.eks_cluster.arn

  bootstrap_self_managed_addons = false

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids = [
      aws_subnet.private_a.id,
      aws_subnet.private_b.id,
    ]

    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = ["183.83.252.11/32"]
  }

  kubernetes_network_config {
    ip_family = "ipv4"
  }

  tags = {
    Name = "${var.project}-eks"
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster]
}
