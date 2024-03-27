#create a variable
variable "eks_cluster_version" {
  type        = string
  default     = "1.28"
  description = "EKS version for the cluster"
}
variable "region" {
  type        = string
  default     = "us-west-2"
  description = "Region for deployment"
}
