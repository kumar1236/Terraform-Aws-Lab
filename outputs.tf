output "aws_instance_public_dns" {
  value       = "http://${aws_instance.nginx1.public_dns}"
  description = "Public DNS Hostname for the EC2 Instance."
}

output "aws_instance_public_ip" {
  value       = aws_instance.nginx1.public_ip
  description = "Public DNS Hostname for the EC2 Instance."
}

output "aws_vpc_id" {
  value       = aws_vpc.kumar_vpc.id
  description = "VPC ID"
}

output "aws_public_subnet_id" {
  value       = aws_subnet.public.id
  description = "Public subnet ID"
}

output "aws_private_subnet_id" {
  value       = aws_subnet.private.id
  description = "Private Subnet ID"
}
