variable "name" {
  description = "Name of the VPC and EKS Cluster"
  type        = string
  default     = "nifi-on-eks"
}

variable "region" {
  description = "Region"
  type        = string
  default     = "us-west-2"
}

variable "eks_cluster_version" {
  description = "EKS Cluster version"
  type        = string
  default     = "1.29"
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.1.0.0/16"
}

variable "public_subnets" {
  description = "Public Subnets CIDRs. 4094 IPs per Subnet"
  type        = list(string)
  default     = ["10.1.192.0/20", "10.1.208.0/20", "10.1.224.0/20"]
}

variable "private_subnets" {
  description = "Private Subnets CIDRs. 16382 IPs per Subnet"
  type        = list(string)
  default     = ["10.1.0.0/18", "10.1.64.0/18", "10.1.128.0/18"]
}

variable "eks_cluster_domain" {
  description = "A Route53 Public Hosted Zone configured in the account where you are deploying this example. E.g. example.com"
  type        = string
}

variable "nifi_sub_domain" {
  description = "Subdomain for NiFi cluster."
  type        = string
  default     = "mynifi"
}

variable "acm_certificate_domain" {
  description = "An ACM Certificate in the account + region where you are deploying this example. A wildcard certificate is preferred, e.g. *.example.com"
  type        = string
}

variable "nifi_username" {
  description = "NiFi login username"
  default     = "admin"
  type        = string
}

variable "enable_amazon_prometheus" {
  description = "Enable AWS Managed Prometheus service"
  type        = bool
  default     = true
}
