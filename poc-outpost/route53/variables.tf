
variable "region" {
  description = "Region"
  type        = string
  default     = "us-west-2"
}

variable "name" {
  description = "Name of the VPC and EKS Cluster"
  type        = string
  default     = "poc-orange-doeks"
}


variable "eks_cluster_version" {
  description = "EKS Cluster version"
  type        = string
  default     = "1.32"
}

variable "cluster_endpoint" {
  description = "Endpoint of the EKS cluster"
  type        = string
  default     = "https://E126CF0ABF5A8A4A01D74B41EBB8C495.gr7.us-west-2.eks.amazonaws.com"
}

variable "main_domain" {
  description = "Main domain for the cluster"
  type        = string
  default     = "orange-eks.com"
}

variable "sub_domain" {
  description = "Subdomain for the cluster"
  type        = string
  default     = "poc.orange-eks.com"
}

variable "shared_alb_name" {
    description = "Name of the shared Application Load Balancer (ALB) for the cluster"
    type        = string
    default     = "pocsharedalb"
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
