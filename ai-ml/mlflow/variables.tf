variable "name" {
  description = "Name of the VPC and EKS Cluster"
  default     = "mlflow-eks"
  type        = string
}

variable "region" {
  description = "Region"
  type        = string
  default     = "us-west-2"
}

variable "eks_cluster_version" {
  description = "EKS Cluster version"
  default     = "1.27"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  default     = "10.1.0.0/16"
  type        = string
}

variable "db_private_subnets" {
  description = "Private Subnets CIDRs. 254 IPs per Subnet/AZ for Airflow DB."
  default     = ["10.0.20.0/26", "10.0.21.0/26"]
  type        = list(string)
}

variable "enable_amazon_prometheus" {
  description = "Enable AWS Managed Prometheus service"
  type        = bool
  default     = true
}

variable "enable_mlflow" {
  description = "Enable MMLflow"
  type        = bool
  default     = true
}