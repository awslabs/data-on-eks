variable "region" {
  description = "Region"
  type        = string
}

variable "name" {
  description = "Name of the VPC, EKS Cluster and Ray cluster"
  type        = string
}

variable "eks_cluster_version" {
  description = "EKS Cluster version"
  type        = string
}
