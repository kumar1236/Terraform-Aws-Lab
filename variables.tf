variable "aws_region" {
  description = "AWS region where we will create the infrastructure."
  type        = string
  default     = "ap-south-1"
}

variable "project" {
  description = "Project name used to name and tag our AWS resources."
  type        = string
  default     = "wp-lab"
}

# Upgrade preparation (baseline observed on 2026-10-29).
# Keep all defaults at the running versions before planning any upgrade.
# Separate targets let us review control-plane, worker and add-on changes in stages.
variable "eks_cluster_version" {
  description = "EKS control-plane Kubernetes version. Advance one minor version per reviewed upgrade."
  type        = string
  default     = "1.36"
}

variable "eks_node_version" {
  description = "Managed-worker Kubernetes version, controlled independently from the control plane."
  type        = string
  default     = "1.36"
}

variable "eks_node_ami_release_version" {
  description = "Explicit AL2023 worker AMI release, initially matching the running node group."
  type        = string
  default     = "1.36.5-20261026"
}

# These are EKS add-on package versions from describe-addon, not container image tags.
# Select replacement versions only after checking compatibility for each upgrade stage.
variable "eks_addon_versions" {
  description = "Reviewed EKS managed add-on versions; fixed defaults prevent automatic latest-version changes."
  type = object({
    pod_identity_agent = string
    vpc_cni            = string
    kube_proxy         = string
    coredns            = string
    ebs_csi            = string
  })
  default = {
    pod_identity_agent = "v1.4.1-eksbuild.3"
    vpc_cni            = "v1.23.2-eksbuild.8"
    kube_proxy         = "v1.36.0-eksbuild.58"
    coredns            = "v1.13.2-eksbuild.62"
    ebs_csi            = "v1.67.2-eksbuild.1"
  }
}
