variable "cluster_name" {
  description = "Name of the VPC and EKS Cluster"
  type        = string
}

variable "region" {
  description = "Region"
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

variable "cognito_user_pool_id" {
  description = "ID of the Cognito user pool for authentication"
  type        = string
}

variable "cognito_custom_domain" {
  description = "Custom domain for Cognito user pool"
  type        = string
}

variable "cluster_issuer_name" {
  description = "Name of the cluster issuer for cert-manager"
  type        = string
}

variable "main_domain" {
  description = "Main domain for the cluster"
  type        = string
}

variable "zone_id" {
  description = "Zone ID for the main domain"
  type        = string
}

variable "wildcard_certificate_arn" {
  description = "ARN of the wildcard certificate for the main domain"
  type        = string
}
