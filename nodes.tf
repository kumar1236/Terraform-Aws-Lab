resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project}-workers"
  node_role_arn   = aws_iam_role.eks_nodes.arn

  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id,
  ]

  # Upgrade preparation: workers previously inherited the control-plane version.
  # Separate targets let the control plane advance before a reviewed worker rollout.
  version = var.eks_node_version

  # Freeze the observed AMI release; select a matching release for each worker upgrade.
  release_version = var.eks_node_ami_release_version
  ami_type        = "AL2023_x86_64_STANDARD"
  instance_types  = ["t3.medium"]
  capacity_type   = "ON_DEMAND"
  disk_size       = 30

  scaling_config {
    desired_size = 2
    min_size     = 2
    max_size     = 3
  }

  # Upgrade: limit unavailable nodes to one; singleton workloads can still be interrupted.
  update_config {
    max_unavailable = 1
  }

  tags = {
    Name = "${var.project}-workers"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_nodes_worker,
    aws_iam_role_policy_attachment.eks_nodes_ecr,
    aws_eks_addon.vpc_cni,
    aws_route_table_association.private_a,
    aws_route_table_association.private_b,
  ]
}
