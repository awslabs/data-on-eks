variable "name" {
  description = "Name of the VPC and EKS Cluster"
  default     = "doeks-workshop"
  type        = string
}

variable "region" {
  description = "region"
  type        = string
  default     = "us-west-2"
}

variable "eks_cluster_version" {
  description = "EKS Cluster version"
  default     = "1.24"
  type        = string
}

variable "tags" {
  description = "Default tags"
  default     = {}
  type        = map(string)
}

variable "vpc_id" {
  description = "VPC CIDR"
  type        = string
}

variable "private_subnets" {
  description = "Private Subnet IDs"
  type        = list(string)
}
