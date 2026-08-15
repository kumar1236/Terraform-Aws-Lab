variable "company" {
  type        = string
  description = "Company name for resource tagging"
  default     = "Moo-Tastic"
}

variable "project" {
  type        = string
  description = "Project name for resource tagging"
}

variable "aws_region" {
  type        = string
  description = "AWS region for deployment"
  default     = "ap-south-1"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC Cidr Block"
  default     = "10.100.0.0/23"
}

variable "enable_dns_hostnames" {
  type        = bool
  description = "Enable DNS hostnames in VPC"
  default     = true
}

variable "vpc_public_subnet" {
  type        = string
  description = "VPC Public Subnet"
  default     = "10.100.0.0/24"
}

variable "vpc_private_subnet" {
  type        = string
  description = "VPC Private Subnet"
  default     = "10.100.1.0/24"
}

variable "map_public_ip_on_launch" {
  type        = bool
  description = "Map a public IP address for Subnet instances"
  default     = true
}

variable "ec2_instance_type" {
  type        = string
  description = "Type for EC2 Instance"
  default     = "t3.micro"
}

variable "http_port" {
  type        = string
  description = "Http port serve from server"
  default     = "80"
}

variable "my_public_ip" {
  type        = string
  description = "Allowing connections to specific IP. Default allows world"
  default     = "0.0.0.0/0"
}
