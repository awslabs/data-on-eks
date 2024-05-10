variable "region" {
  type        = string
  default     = "us-west-2"
  description = "Region for deployment"
}

variable "name" {
  description = "Name of the VPC and EKS Cluster"
  default     = "emr-eks-flink"
  type        = string
}

variable "eks_cluster_version" {
  type        = string
  default     = "1.29"
  description = "EKS version for the cluster"
}
