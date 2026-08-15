/*
This Terraform configuration set up

*/

terraform {
  required_providers {
    aws = {
      source : "hashicorp/aws"
    }
  }
}

############################################
# PROVIDERS
############################################

provider "aws" {
  region = var.aws_region
}

##################################################################################
# DATA
##################################################################################

data "aws_ssm_parameter" "amzn2_linux" {
  name = "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
}

############################################
# RESOURCES
############################################

resource "aws_vpc" "kumar_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = var.enable_dns_hostnames

  tags = merge(local.common_tags, { Name = lower("${local.common_tags.project}-vpc") })
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.kumar_vpc.id
  cidr_block              = var.vpc_public_subnet
  map_public_ip_on_launch = var.map_public_ip_on_launch

  tags = merge(local.common_tags, { Name = lower("${local.common_tags.project}-pub-subnet") })
}

resource "aws_subnet" "private" {
  vpc_id     = aws_vpc.kumar_vpc.id
  cidr_block = var.vpc_private_subnet

  tags = merge(local.common_tags, { Name = lower("${local.common_tags.project}-pri-subnet") })
}

resource "aws_internet_gateway" "kumar_igw" {
  vpc_id = aws_vpc.kumar_vpc.id

  tags = merge(local.common_tags, { Name = lower("${local.common_tags.project}-igw") })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.kumar_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.kumar_igw.id
  }

  tags = merge(local.common_tags, { Name = lower("${local.common_tags.project}-rt") })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "ec2_security_group" {
  name        = "ec2-security-group"
  description = "Default EC2 Security Group"
  vpc_id      = aws_vpc.kumar_vpc.id

  # Inbound SSH access from anywhere
  ingress {
    description = "SSH Access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_public_ip]
  }

  # Outbound Internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = lower("${local.common_tags.project}-sg") })
}

# Inbound HTTP access from anywhere
resource "aws_security_group_rule" "http_inbound" {
  type              = "ingress"
  from_port         = var.http_port
  to_port           = var.http_port
  protocol          = "tcp"
  cidr_blocks       = [var.my_public_ip]
  security_group_id = aws_security_group.ec2_security_group.id
}

# Create Ec2 Instance
resource "aws_instance" "nginx1" {
  ami                    = nonsensitive(data.aws_ssm_parameter.amzn2_linux.value)
  instance_type          = var.ec2_instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ec2_security_group.id]

  user_data = templatefile("./templates/startup_script.tpl", { project = var.project })

  tags = merge(local.common_tags, { Name = lower("${local.common_tags.project}-ec2") })

}