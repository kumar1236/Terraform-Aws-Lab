# Terraform AWS Lab

This repository contains a small AWS lab environment managed with Terraform. It is intended for learning and experimentation and can be extended as the lab grows.

## Architecture

The current configuration creates:

- An AWS VPC with DNS hostnames enabled
- One public subnet and one private subnet
- An internet gateway
- A public route table and subnet association
- A security group for SSH and HTTP access
- An Amazon Linux 2 EC2 instance running Nginx
- Common resource tags derived from the company and project names

The private subnet is created without a NAT gateway or private route table, so it does not currently have outbound internet access.

## Repository structure

```text
.
|-- locals.tf
|-- main.tf
|-- outputs.tf
|-- variables.tf
|-- terraform.tfvars        # Local values; ignored by Git
`-- templates/
    `-- startup_script.tpl  # EC2 bootstrap script
```

## Prerequisites

- An AWS account
- Terraform installed
- AWS credentials configured locally
- Permission to create VPC, EC2, SSM, networking, and security-group resources

Configure AWS credentials using your preferred method, for example:

```powershell
aws configure
```

Do not commit AWS credentials, Terraform state, or your real `terraform.tfvars` file.

## Configuration

Create a local `terraform.tfvars` file:

```hcl
project               = "aws-lab"
aws_region            = "ap-south-1"
ec2_instance_type     = "t3.micro"
my_public_ip          = "203.0.113.10/32"
```

Replace the example IP address with your public IP in CIDR notation. Avoid the default `0.0.0.0/0` for SSH access outside a temporary lab environment.

## Deploy

Format and validate the configuration before reviewing the execution plan:

```powershell
terraform init
terraform fmt -recursive
terraform validate
terraform plan
```

Create the infrastructure only after reviewing the plan:

```powershell
terraform apply
```

After deployment, Terraform outputs the instance URL, public IP address, VPC ID, and subnet IDs:

```powershell
terraform output
```

## Clean up

Destroy the lab resources when they are no longer needed to avoid ongoing AWS charges:

```powershell
terraform destroy
```

Review the destroy plan carefully before confirming it.

## Importing existing resources later

Existing AWS resources can be brought under Terraform management later with `terraform import` or Terraform import blocks. Define a matching resource in the configuration, back up the state, import the AWS resource, and then run `terraform plan` to reconcile configuration differences.

Example:

```powershell
terraform import aws_vpc.kumar_vpc vpc-0123456789abcdef0
terraform plan
```

Never import a resource without first understanding how its current AWS settings map to the Terraform configuration.

## Development workflow

Make changes on `develop`, validate them, and push the branch:

```powershell
git switch develop
git pull --ff-only origin develop
terraform fmt -recursive
terraform validate
terraform plan
git add <files>
git commit -m "Describe the change"
git push origin develop
```

Open a pull request from `develop` into the protected `main` branch after testing.
