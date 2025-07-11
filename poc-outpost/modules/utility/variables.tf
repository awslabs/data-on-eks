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

variable "oidc_provider_arn" {
  description = "ARN of the OIDC provider for the EKS cluster"
  type        = string
}

variable "tags" {
  type        = map(string)
  description = "Tags à appliquer aux ressources"
}

variable "cognito_custom_domain" {
  description = "Custom domain for Cognito"
  type        = string
}

variable "cluster_issuer_name" {
  description = "Name of the cluster issuer for cert-manager"
  type        = string
}
