variable "name" {
  description = "Name of the VPC and EKS Cluster"
  type        = string
  default     = "emr-spark-rapids"
}

variable "region" {
  description = "Region"
  default     = "us-west-2"
  type        = string
}

variable "eks_cluster_version" {
  description = "EKS Cluster version"
  type        = string
  default     = "1.26"
}

variable "tags" {
  description = "Default tags"
  type        = map(string)
  default     = {}
}

# VPC with 2046 IPs (10.1.0.0/21) and 2 AZs
variable "vpc_cidr" {
  description = "VPC CIDR. This should be a valid private (RFC 1918) CIDR range"
  type        = string
  default     = "10.1.0.0/16"
}

# Routable Public subnets with NAT Gateway and Internet Gateway
# 65 IPs per subnet/AZ
variable "public_subnets" {
  description = "Public Subnets CIDRs. 62 IPs per Subnet/AZ"
  type        = list(string)
  default     = ["10.1.0.0/26", "10.1.0.64/26"]
}

# Routable Private subnets only for Private NAT Gateway -> Transit Gateway -> Second VPC for overlapping overlapping CIDRs
# 256 IPs per subnet/AZ
variable "private_subnets" {
  description = "Private Subnets CIDRs. 254 IPs per Subnet/AZ for Private NAT + NLB + Airflow + EC2 Jumphost etc."
  type        = list(string)
  default     = ["10.1.1.0/24", "10.1.2.0/24"]
}

# RFC6598 range 100.64.0.0/10 for EKS Data Plane
# Note you can only use /16 range to VPC. You can add multiples of /16 if required
variable "secondary_cidr_blocks" {
  description = "Secondary CIDR blocks to be attached to VPC"
  type        = string
  default     = "100.64.0.0/16"
}

variable "enable_vpc_endpoints" {
  description = "Enable VPC Endpoints"
  type        = string
  default     = false
}

variable "enable_amazon_prometheus" {
  description = "Enable AWS Managed Prometheus service"
  default     = true
  type        = bool
}

variable "enable_kubecost" {
  description = "Enable Kubecost"
  default     = false
  type        = bool
}
