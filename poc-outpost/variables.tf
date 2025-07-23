
variable "region" {
  description = "Region"
  type        = string
  default     = "us-west-2"
}

variable "name" {
  description = "Name of the VPC and EKS Cluster"
  type        = string
  default     = "poc-orange-doeks-otl4"
}

variable "outpost_name" {
  description = "Name of the Outpost"
  type        = string
  default     = "OTL4"
}

# VPC
variable "vpc_cidr" {
  description = "VPC CIDR. This should be a valid private (RFC 1918) CIDR range"
  default     = "10.3.0.0/16"
  type        = string
}

variable "eks_cluster_version" {
  description = "EKS Cluster version"
  type        = string
  default     = "1.32"
}

variable "default_node_group_type" {
  description = "Default node group type for the EKS cluster"
  type        = string
  default     = "doeks"
}

variable "hosted_zone_id" {
  description = "Hosted Zone ID Route53"
  type        = string
  default     = "Z05779363BJIUL4KDL4V1"
}

# Liste des noms de domaine à enregistrer dans Route53 pointant vers le LB Network ciblant l'ingress controller ISTIO
variable "domaine_name_route53" {
  description = "Liste des noms de domaine a enregistrer dans Route53"
  default = [
    "albtest-otl4.orange-eks.com",
    "trino-otl4.orange-eks.com",
    "airflowalb4.orange-eks.com",
    "nifi-otl4.orange-eks.com"
  ]
  type = list(string)
}

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

variable "enable_trino" {
  description = "Enable Trino"
  type        = bool
  default     = true
}

variable "enable_kafka" {
  description = "enable Kafka cluster"
  type        = bool
  default     = true
}

variable "cluster_issuer_name" {
  description = "Name of the cluster issuer for cert-manager"
  type        = string
  default     = "letsencrypt-http-private"
}

variable "main_domain" {
  description = "Main domain for the cluster"
  type        = string
  default     = "orange-eks.com"
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
