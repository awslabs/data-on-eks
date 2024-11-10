variable "name" {
  description = "Name of the VPC and EKS Cluster"
  default     = "trino-on-eks"
  type        = string
}

variable "region" {
  description = "Region"
  type        = string
  default     = "us-west-2"
}

variable "eks_cluster_version" {
  description = "EKS Cluster version"
  default     = "1.31"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  default     = "10.1.0.0/16"
  type        = string
}

# Access Entries for Cluster Access Control
variable "access_entries" {
  description = <<EOT
Map of access entries to be added to the EKS cluster. This can include IAM users, roles, or groups that require specific access permissions (e.g., admin access, developer access) to the cluster.
The map should follow the structure:
{
  "role_arn": "arn:aws:iam::123456789012:role/AdminRole",
  "username": "admin"
}
EOT
  type        = any
  default     = {}
}

# KMS Key Admin Roles
variable "kms_key_admin_roles" {
  description = <<EOT
A list of AWS IAM Role ARNs to be added to the KMS (Key Management Service) policy. These roles will have administrative permissions to manage encryption keys used for securing sensitive data within the cluster.
Ensure that these roles are trusted and have the necessary access to manage encryption keys.
EOT
  type        = list(string)
  default     = []
}
