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

  tags = local.common_tags
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.kumar_vpc.id
  cidr_block              = var.vpc_public_subnet
  map_public_ip_on_launch = var.map_public_ip_on_launch

  tags = local.common_tags
}

resource "aws_subnet" "private" {
  vpc_id     = aws_vpc.kumar_vpc.id
  cidr_block = var.vpc_private_subnet

  tags = local.common_tags
}

resource "aws_internet_gateway" "kumar_igw" {
  vpc_id = aws_vpc.kumar_vpc.id

  tags = local.common_tags
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.kumar_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.kumar_igw.id
  }

  tags = local.common_tags
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
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound Internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

# Inbound HTTP access from anywhere
resource "aws_security_group_rule" "http_inbound" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ec2_security_group.id
}

# Create Ec2 Instance
resource "aws_instance" "nginx1" {
  ami                    = nonsensitive(data.aws_ssm_parameter.amzn2_linux.value)
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ec2_security_group.id]

  user_data = <<EOF
#! /bin/bash
sudo amazon-linux-extras install -y nginx1
sudo service nginx start
sudo rm /usr/share/nginx/html/index.html
echo '<html><head><title>MOO Team Server</title></head><body style=\"background-color:#1F778D\"><p style=\"text-align: center;\"><span style=\"color:#FFFFFF;\"><span style=\"font-size:28px;\">You did it! Have a &#127790;</span></span></p></body></html>' | sudo tee /usr/share/nginx/html/index.html
EOF

  tags = local.common_tags

}
