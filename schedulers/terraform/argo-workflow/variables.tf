variable "name" {
  description = "Name of the VPC and EKS Cluster"
  default     = "argoworkflows-eks"
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

variable "enable_amazon_prometheus" {
  description = "Enable AWS Managed Prometheus service"
  type        = bool
  default     = true
}

variable "enable_yunikorn" {
  default     = true
  description = "Enable Apache YuniKorn Scheduler"
  type        = bool
}
