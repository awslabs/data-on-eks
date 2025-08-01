variable "name" {
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

variable "cluster_version" {
  description = "EKS Cluster version"
  type        = string
}


variable "cluster_endpoint" {
  description = "Endpoint of the EKS cluster"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the OIDC provider for the EKS cluster"
  type        = string
}

variable "cluster_issuer_name" {
  description = "Name of the cluster issuer for the OIDC provider"
  type        = string
}

variable "main_domain" {
    description = "Main domain for the cluster"
    type        = string
}

variable "private_subnets_cidr" {
    description = "List of private subnets CIDR blocks"
    type        = list(string)
}

variable "vpc_id" {
    description = "VPC ID where the EKS cluster is deployed"
    type        = string
}


variable "db_subnet_group_name" {
    description = "Name of the DB subnet group"
    type        = string
}

variable "ec_subnet_group_name" {
    description = "Name of the ElastiCache subnet group"
    type        = string
}

variable "security_group_id" {
    description = "Security group ID for the Superset deployment"
    type        = string
}

