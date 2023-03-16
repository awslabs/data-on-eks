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

variable "enable_karpenter" {
  description = "Enable Karpenter autoscaler add-on"
  type        = bool
  default     = true
}

variable "enable_yunikorn" {
  default     = false
  description = "Enable Apache YuniKorn Scheduler"
  type        = bool
}

variable "enable_kubecost" {
  description = "Enable Kubecost add-on"
  type        = bool
  default     = true
}
