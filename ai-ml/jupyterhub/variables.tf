variable "name" {
  description = "Name of the VPC and EKS Cluster"
  default     = "jupyterhub-on-eks"
  type        = string
}

variable "region" {
  description = "region"
  type        = string
  default     = "us-west-2"
}

variable "eks_cluster_version" {
  description = "EKS Cluster version"
  default     = "1.27"
  type        = string
}

# VPC with 2046 IPs (10.1.0.0/21) and 2 AZs
variable "vpc_cidr" {
  description = "VPC CIDR. This should be a valid private (RFC 1918) CIDR range"
  default     = "10.1.0.0/21"
  type        = string
}

# RFC6598 range 100.64.0.0/10
# Note you can only /16 range to VPC. You can add multiples of /16 if required
variable "secondary_cidr_blocks" {
  description = "Secondary CIDR blocks to be attached to VPC"
  default     = ["100.64.0.0/16"]
  type        = list(string)
}

variable "cognito_custom_domain" {
  description = "URL of the jupyter notebook. e.g..,https://cog.yourdomain.com"
  type        = string
  default     = "ml-jupy" #  Domain cannot contain reserved word: cognito
}

# NOTE: You need to use private domain or public domain name with ACM certificate
# This website doc will show you how to create free public domain name with ACM certificate for testing purpose only
variable "acm_certificate_domain" {
  type        = string
  description = "Enter domain name with wildcard and ensure ACM certificate is created for this domain name, e.g. *.example.com"
  default     = ""
}
