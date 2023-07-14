variable "name" {
  description = "Name of the VPC and EKS Cluster"
  type        = string
  default     = "emr-eks-karpenter"
}

variable "region" {
  description = "Region"
  default     = "us-west-2"
  type        = string
}

variable "eks_cluster_version" {
  description = "EKS Cluster version"
  type        = string
  default     = "1.27"
}

variable "tags" {
  description = "Default tags"
  type        = map(string)
  default     = {}
}

# VPC with 2046 IPs
variable "vpc_cidr" {
  description = "VPC CIDR. This should be a valid private (RFC 1918) CIDR range"
  type        = string
  default     = "10.1.0.0/16"
}

# Routable Public subnets with NAT Gateway and Internet Gateway
variable "public_subnets" {
  description = "Public Subnets CIDRs. 62 IPs per Subnet/AZ"
  type        = list(string)
  default     = ["10.1.0.0/26", "10.1.0.64/26"]
}

# Routable Private subnets only for Private NAT Gateway -> Transit Gateway -> Second VPC for overlapping overlapping CIDRs
variable "private_subnets" {
  description = "Private Subnets CIDRs. 254 IPs per Subnet/AZ for Private NAT + NLB + Airflow + EC2 Jumphost etc."
  type        = list(string)
  default     = ["10.1.1.0/24", "10.1.2.0/24"]
}

# RFC6598 range 100.64.0.0/10
# Note you can only /16 range to VPC. You can add multiples of /16 if required
variable "secondary_cidr_blocks" {
  description = "Secondary CIDR blocks to be attached to VPC"
  type        = list(string)
  default     = ["100.64.0.0/16"]
}

# EKS Worker nodes and pods will be placed on these subnets. Each Private subnet can get 32766 IPs.
# RFC6598 range 100.64.0.0/10
variable "eks_data_plane_subnet_secondary_cidr" {
  description = "Secondary CIDR blocks. 32766 IPs per Subnet per Subnet/AZ for EKS Node and Pods"
  type        = list(string)
  default     = ["100.64.0.0/17", "100.64.128.0/17"]
}

variable "enable_vpc_endpoints" {
  description = "Enable VPC Endpoints"
  type        = string
  default     = false
}

variable "enable_yunikorn" {
  description = "Enable Apache YuniKorn Scheduler"
  type        = bool
  default     = false
}

variable "enable_fsx_for_lustre" {
  description = "Deploys fsx for lustre addon, storage class and static FSx for Lustre filesystem for EMR"
  type        = bool
  default     = false
}

variable "enable_aws_cloudwatch_metrics" {
  description = "Enable Cloudwatch metrics"
  type        = bool
  default     = true
}

variable "enable_amazon_prometheus" {
  description = "Enable AWS Managed Prometheus service"
  type        = bool
  default     = false
}

variable "enable_kubecost" {
  description = "Enable Kubecost"
  type        = bool
  default     = false
}

variable "enable_emr_spark_operator" {
  description = "Enable the Spark Operator to submit jobs with EMR Runtime"
  default     = false
  type        = bool
}
