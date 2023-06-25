variable "name" {
  description = "Name of the VPC and EKS Cluster"
  default     = "emr-spark-rapids"
  type        = string
}
variable "region" {
  description = "region"
  type        = string
  default     = "us-west-2"
}
variable "eks_cluster_version" {
  description = "EKS Cluster version"
  default     = "1.26"
  type        = string
}

variable "tags" {
  description = "Default tags"
  default     = {}
  type        = map(string)
}

# VPC with 2046 IPs (10.1.0.0/21) and 2 AZs
variable "vpc_cidr" {
  description = "VPC CIDR. This should be a valid private (RFC 1918) CIDR range"
  default     = "10.1.0.0/16"
  type        = string
}

# Routable Public subnets with NAT Gateway and Internet Gateway
# 65 IPs per subnet/AZ
variable "public_subnets" {
  description = "Public Subnets CIDRs. 62 IPs per Subnet/AZ"
  default     = ["10.1.0.0/26", "10.1.0.64/26"]
  type        = list(string)
}

# Routable Private subnets only for Private NAT Gateway -> Transit Gateway -> Second VPC for overlapping overlapping CIDRs
# 256 IPs per subnet/AZ
variable "private_subnets" {
  description = "Private Subnets CIDRs. 254 IPs per Subnet/AZ for Private NAT + NLB + Airflow + EC2 Jumphost etc."
  default     = ["10.1.1.0/24", "10.1.2.0/24"]
  type        = list(string)
}

# RFC6598 range 100.64.0.0/10 for EKS Data Plane
# Note you can only use /16 range to VPC. You can add multiples of /16 if required
variable "secondary_cidr_blocks" {
  description = "Secondary CIDR blocks to be attached to VPC"
  default     = "100.64.0.0/16"
  type        = string
}

variable "enable_vpc_endpoints" {
  description = "Enable VPC Endpoints"
  default     = false
  type        = string
}

variable "enable_amazon_prometheus" {
  description = "Enable AWS Managed Prometheus service"
  type        = bool
  default     = true
}

variable "enable_grafana" {
  description = "Enable Grafana"
  type        = bool
  default     = true
}
variable "enable_kubecost" {
  description = "Enable Kubecost"
  type        = bool
  default     = false
}
