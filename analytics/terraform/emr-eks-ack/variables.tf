variable "name" {
  description = "Name of the VPC and EKS Cluster"
  default     = "emr-eks-ack"
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

variable "vpc_cidr" {
  description = "VPC CIDR"
  default     = "10.1.0.0/16"
  type        = string
}

variable "enable_ack" {
  description = "Enable ACK Controller for EMR on EKS"
  default     = true
  type        = bool
}

variable "enable_crossplane" {
  description = "Enable Crossplane for EKS"
  default     = false
  type        = bool
}
