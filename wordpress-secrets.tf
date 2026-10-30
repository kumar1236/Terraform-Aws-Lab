# Only secret metadata is managed here. Initialize the value from your laptop;
# database passwords must never enter Terraform configuration or state.
resource "aws_secretsmanager_secret" "wordpress_database" {
  name                    = "${var.project}/wordpress/database"
  description             = "Initial WordPress database credentials consumed by External Secrets Operator."
  recovery_window_in_days = 7

  tags = {
    Name = "${var.project}-wordpress-database"
  }
}

resource "aws_iam_role" "external_secrets" {
  name        = "${var.project}-external-secrets-role"
  description = "Read the WordPress database secret through EKS Pod Identity."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      Action = ["sts:AssumeRole", "sts:TagSession"]
      Condition = {
        StringEquals = {
          "aws:RequestTag/eks-cluster-arn"            = aws_eks_cluster.main.arn
          "aws:RequestTag/kubernetes-namespace"       = "external-secrets"
          "aws:RequestTag/kubernetes-service-account" = "external-secrets"
        }
      }
    }]
  })

  tags = {
    Name = "${var.project}-external-secrets-role"
  }
}

resource "aws_iam_role_policy" "external_secrets" {
  name = "${var.project}-read-wordpress-secret"
  role = aws_iam_role.external_secrets.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      Resource = aws_secretsmanager_secret.wordpress_database.arn
    }]
  })
}

resource "aws_eks_pod_identity_association" "external_secrets" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "external-secrets"
  service_account = "external-secrets"
  role_arn        = aws_iam_role.external_secrets.arn

  depends_on = [
    aws_iam_role_policy.external_secrets,
    aws_eks_addon.pod_identity_agent,
  ]
}
