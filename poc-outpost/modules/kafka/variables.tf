variable "name" {
  description = "Name of the VPC and EKS Cluster"
  type        = string
}

variable "region" {
  description = "Region"
  type        = string
}

variable "cluster_version" {
  description = "EKS Cluster version"
  type        = string
}

variable "cluster_endpoint" {
  description = "EKS Cluster endpoint"
  type        = string
}

variable "tags" {
  type        = map(string)
  description = "Tags à appliquer aux ressources"
}
variable "karpenter_node_iam_role_name" {
  description = "The name of the IAM role created for Karpenter nodes"
  type        = string
}
variable "oidc_provider_arn" {
  description = "ARN of the OIDC provider for the EKS cluster"
  type        = string
}