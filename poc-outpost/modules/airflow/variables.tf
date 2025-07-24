variable "name" {
  description = "Name of the VPC and EKS Cluster"
  type        = string
}

variable "region" {
  description = "Region"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the OIDC provider for the EKS cluster"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC where the EKS cluster will be deployed"
  type        = string
}

variable "private_subnets_cidr" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
}

variable "db_subnets_group_name" {
  description = "Name of the DB subnets group"
  type        = string
}

variable "tags" {
  type        = map(string)
  description = "Tags à appliquer aux ressources"
}

variable "cluster_issuer_name" {
    description = "Name of the ClusterIssuer for cert-manager"
    type        = string
}

variable "main_domain" {
    description = "Main domain for the cluster"
    type        = string
}
