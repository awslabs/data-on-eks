variable "name" {
  description = "Name of the VPC and EKS Cluster"
  default     = "emr-eks-karpenter"
  type        = string
}

variable "region" {
  description = "region"
  type        = string
  default     = "us-west-2"
}

variable "tags" {
  description = "Default tags"
  default     = {}
  type        = map(string)
}
