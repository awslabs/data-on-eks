variable "region" {
  description = "Region"
  type        = string
  default     = "us-west-2"
}

variable "name" {
  description = "Name of the VPC and EKS Cluster"
  type        = string
  default     = "kafka-on-eks"
}

variable "eks_cluster_version" {
  description = "EKS Cluster version"
  type        = string
  default     = "1.29"
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.1.0.0/16"
}

variable "enable_amazon_prometheus" {
  description = "Enable AWS Managed Prometheus service"
  type        = bool
  default     = true
}
