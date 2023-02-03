variable "name" {
  description = "Name of the VPC and EKS Cluster"
  default     = "nifi-on-eks"
  type        = string
}

variable "region" {
  description = "region"
  type        = string
  default     = "us-west-2"
}

variable "eks_cluster_version" {
  description = "EKS Cluster version"
  default     = "1.24"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  default     = "10.1.0.0/16"
  type        = string
}

variable "public_subnets" {
  description = "Public Subnets CIDRs. 4094 IPs per Subnet"
  default     = ["10.1.192.0/20", "10.1.208.0/20", "10.1.224.0/20"]
  type        = list(string)
}

variable "private_subnets" {
  description = "Private Subnets CIDRs. 16382 IPs per Subnet"
  default     = ["10.1.0.0/18", "10.1.64.0/18", "10.1.128.0/18"]
  type        = list(string)
}

variable "eks_cluster_domain" {
  type        = string
  description = "A Route53 Public Hosted Zone configured in the account where you are deploying this example. E.g. example.com"
}

variable "nifi_sub_domain" {
  type        = string
  description = "Route53 DNS record for NiFi cluster."
  default     = "mynifi"
}

variable "acm_certificate_domain" {
  type        = string
  description = "An ACM Certificate in the account + region where you are deploying this example. A wildcard certificate is preferred, e.g. *.example.com"
}

variable "nifi_username" {
  type        = string
  description = "NiFi login username"
  default = "admin"
}
