# variable "name" {
#   description = "Name of the VPC and EKS Cluster"
#   type        = string
# }

variable "tags" {
  type        = map(string)
  description = "Tags à appliquer aux ressources"
}

variable "namespace" {
  type        = string
  description = "Namespace istio cible"
  default     = "istio-system"
}

variable "region" {
  type        = string
  description = "Region AWS cible"
}

variable "eks_cluster_name" {
  type        = string
  description = "Cluster EKS Cible"
}