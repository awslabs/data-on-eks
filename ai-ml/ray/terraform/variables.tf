variable "region" {
  description = "AWS Region"
  type        = string
  default     = "us-west-2"
}

variable "name" {
  description = "Name of the VPC, EKS Cluster and Ray cluster"
  default     = "ray-cluster"
  type        = string
}

variable "eks_cluster_version" {
  description = "EKS Cluster version"
  default     = "1.25"
  type        = string
}
