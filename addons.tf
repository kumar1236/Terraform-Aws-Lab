# Upgrade preparation: replace most_recent version lookups with explicit pins.
# Defaults match the five running add-ons. Review compatibility before changing a pin.
# Removing version data sources does not remove or recreate the managed add-ons.

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name  = aws_eks_cluster.main.name
  addon_name    = "eks-pod-identity-agent"
  addon_version = var.eks_addon_versions.pod_identity_agent

  tags = {
    Name = "${var.project}-pod-identity-agent"
  }
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name  = aws_eks_cluster.main.name
  addon_name    = "vpc-cni"
  addon_version = var.eks_addon_versions.vpc_cni

  pod_identity_association {
    role_arn        = aws_iam_role.vpc_cni.arn
    service_account = "aws-node"
  }

  tags = {
    Name = "${var.project}-vpc-cni"
  }

  depends_on = [
    aws_eks_addon.pod_identity_agent,
    aws_iam_role_policy_attachment.vpc_cni,
  ]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name  = aws_eks_cluster.main.name
  addon_name    = "kube-proxy"
  addon_version = var.eks_addon_versions.kube_proxy

  tags = {
    Name = "${var.project}-kube-proxy"
  }

  depends_on = [aws_eks_node_group.main]
}

resource "aws_eks_addon" "coredns" {
  cluster_name  = aws_eks_cluster.main.name
  addon_name    = "coredns"
  addon_version = var.eks_addon_versions.coredns

  tags = {
    Name = "${var.project}-coredns"
  }

  depends_on = [
    aws_eks_node_group.main,
    aws_eks_addon.kube_proxy,
  ]
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name  = aws_eks_cluster.main.name
  addon_name    = "aws-ebs-csi-driver"
  addon_version = var.eks_addon_versions.ebs_csi

  pod_identity_association {
    role_arn        = aws_iam_role.ebs_csi.arn
    service_account = "ebs-csi-controller-sa"
  }

  tags = {
    Name = "${var.project}-ebs-csi"
  }

  depends_on = [
    aws_eks_node_group.main,
    aws_eks_addon.pod_identity_agent,
    aws_eks_addon.coredns,
    aws_iam_role_policy_attachment.ebs_csi,
  ]
}
