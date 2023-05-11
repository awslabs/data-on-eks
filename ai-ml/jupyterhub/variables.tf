variable "name" {
  description = "Name of the VPC and EKS Cluster"
  default     = "jupyterhub-on-eks"
  type        = string
}

variable "region" {
  description = "region"
  type        = string
  default     = "us-east-1"
}

variable "eks_cluster_version" {
  description = "EKS Cluster version"
  default     = "1.25"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  default     = "10.2.0.0/16"
  type        = string
}

variable "public_subnets" {
  description = "Public Subnets CIDRs. 4094 IPs per Subnet"
  default     = ["10.2.192.0/20", "10.2.208.0/20", "10.2.224.0/20"]
  type        = list(string)
}

variable "private_subnets" {
  description = "Private Subnets CIDRs. 16382 IPs per Subnet"
  default     = ["10.2.0.0/18", "10.2.64.0/18", "10.2.128.0/18"]
  type        = list(string)
}

variable "cognito_domain" {
  description = "URL of the jupyter notebook."
  type        = string
  default     = "cog-jupyterhub"
}

variable "jupyterhub_username" {
  type        = string
  description = "jupyterhub login username"
  default     = "admin"
}

variable "acm_certificate_domain" {
  type        = string
  description = "An ACM Certificate in the account + region where you are deploying this example. A wildcard certificate is preferred, e.g. *.example.com"
}

