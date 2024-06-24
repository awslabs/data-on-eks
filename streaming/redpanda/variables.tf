variable "name" {
  description = "Name for Resoucres created - dokeks-redpanda"
  default     = "doeks-redpanda"
  type        = string
}
variable "region" {
  description = "Default Region"
  default     = "us-west-2"
  type        = string
}
variable "eks_cluster_version" {
  description = "EKS Cluster Version"
  default     = "1.28"
  type        = string
}
variable "vpc_cidr" {
  description = "VPC CIDR"
  default     = "172.16.0.0/16"
  type        = string
}
variable "public_subnets" {
  description = "Public Subnets with 126 IPs"
  default     = ["172.16.255.0/25", "172.16.255.128/25"]
  type        = list(string)
}

variable "private_subnets" {
  description = "Private Subnets with 510 IPs"
  default     = ["172.16.0.0/23", "172.16.2.0/23"]
  type        = list(string)
}
#---------------------------------------
# Prometheus Enable
#---------------------------------------
variable "enable_amazon_prometheus" {
  description = "Enable AWS Managed Prometheus service"
  type        = bool
  default     = true
}

#---------------------------------------
# Redpanda Config
#---------------------------------------
variable "redpanda_username" {
  default     = "superuser"
  description = "Default Super Username for Redpanda deployment"
  type        = string
}
variable "redpanda_domain" {
  default     = "customredpandadomain.local"
  description = "Repanda Custom Domain"
  type        = string
}
