variable "eks_cluster_domain" {
  description = "Optional Route53 domain for the cluster."
  type        = string
  default     = ""
}

variable "acm_certificate_domain" {
  description = "Optional Route53 certificate domain"
  type        = string
  default     = null
}

variable "region" {
  description = "AWS Region"
  type        = string
  default     = "us-west-2"
}

variable "name" {
  description = "Name of the VPC and EKS Cluster"
  default     = "ray"
  type        = string
}

variable "eks_cluster_version" {
  description = "EKS Cluster version"
  default     = "1.23"
  type        = string
}

variable "tags" {
  description = "Default tags"
  default     = {}
  type        = map(string)
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  default     = "10.1.0.0/16"
  type        = string
}
