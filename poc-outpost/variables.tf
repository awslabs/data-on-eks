
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

variable "outpost_name" {
  description = "Name of the Outpost"
  type        = string
  default     = "OTL5"
}

# VPC
variable "vpc_cidr" {
  description = "VPC CIDR. This should be a valid private (RFC 1918) CIDR range"
  default     = "10.0.0.0/16"
  type        = string
}

variable "eks_cluster_version" {
  description = "EKS Cluster version"
  type        = string
  default     = "1.32"
}

# # Routable Public subnets with NAT Gateway and Internet Gateway. Not required for fully private clusters
# variable "public_subnets" {
#   description = "Public Subnets CIDRs. 62 IPs per Subnet/AZ"
#   default     = ["10.1.0.0/26", "10.1.0.64/26"]
#   type        = list(string)
# }

# # Routable Private subnets only for Private NAT Gateway -> Transit Gateway -> Second VPC for overlapping overlapping CIDRs
# variable "private_subnets" {
#   description = "Private Subnets CIDRs. 254 IPs per Subnet/AZ for Private NAT + NLB + Airflow + EC2 Jumphost etc."
#   default     = ["10.1.1.0/24", "10.1.2.0/24"]
#   type        = list(string)
# }

# # RFC6598 range 100.64.0.0/10
# # Note you can only /16 range to VPC. You can add multiples of /16 if required
# variable "secondary_cidr_blocks" {
#   description = "Secondary CIDR blocks to be attached to VPC"
#   default     = ["100.64.0.0/16"]
#   type        = list(string)
# }

# # EKS Worker nodes and pods will be placed on these subnets. Each Private subnet can get 32766 IPs.
# # RFC6598 range 100.64.0.0/10
# variable "eks_data_plane_subnet_secondary_cidr" {
#   description = "Secondary CIDR blocks. 32766 IPs per Subnet per Subnet/AZ for EKS Node and Pods"
#   default     = ["100.64.0.0/17", "100.64.128.0/17"]
#   type        = list(string)
# }

variable "enable_amazon_prometheus" {
  description = "Enable Amazon Prometheus for monitoring"
  type        = bool
  default     = true
}

variable "enable_amazon_grafana" {
  description = "Enable Amazon Grafana for monitoring"
  type        = bool
  default     = true
}

variable "enable_airflow" {
  description = "Enable Apache Airflow"
  type        = bool
  default     = true
}

variable "cluster_issuer_name" {
  description = "Name of the cluster issuer for cert-manager"
  type        = string
  default     = "poc-eks-cluster-issuer"
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
