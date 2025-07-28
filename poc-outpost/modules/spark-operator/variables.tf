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

variable "oidc_provider_arn" {
    description = "ARN of the OIDC provider for the EKS cluster"
    type        = string
}

variable "karpenter_node_iam_role_name" {
    description = "The name of the IAM role created for Karpenter nodes"
    type        = string
}

variable "spark_teams" {
  description = "List of all teams (namespaces) that will use Spark Operator"
  type        = list(string)
}

variable "outpost_name" {
  type        = string
  description = "Name of the Outpost"
  default     = "OTL4"
}

variable "output_subnet_id" {
  type        = string
  description = "Outpost subnet id"
}

variable "vpc_id" {
  description = "ID of the VPC where the EKS cluster will be deployed"
  type        = string
}