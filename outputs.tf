output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of public subnet A and public subnet B."
  value = [
    aws_subnet.public_a.id,
    aws_subnet.public_b.id,
  ]
}

output "private_subnet_ids" {
  description = "IDs of the private subnets used by EKS and its worker nodes."
  value = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id,
  ]
}

output "eks_cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.main.name
}

output "eks_cluster_endpoint" {
  description = "Kubernetes API endpoint; access follows the cluster private and public endpoint settings."
  value       = aws_eks_cluster.main.endpoint
}

output "eks_node_group_name" {
  description = "Name of the managed EC2 worker node group."
  value       = aws_eks_node_group.main.node_group_name
}

output "ecr_repository_url" {
  description = "Repository URL used when tagging and pushing container images."
  value       = aws_ecr_repository.app.repository_url
}

output "ecr_repository_arn" {
  description = "Repository ARN used in IAM policies and AWS resource references."
  value       = aws_ecr_repository.app.arn
}

output "wordpress_database_secret_name" {
  description = "Secrets Manager secret name to initialize outside Terraform state."
  value       = aws_secretsmanager_secret.wordpress_database.name
}
