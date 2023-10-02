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

# VPC with 2046 IPs (10.1.0.0/21) and 2 AZs
variable "vpc_cidr" {
  description = "VPC CIDR. This should be a valid private (RFC 1918) CIDR range"
  type        = string
  default     = "10.1.0.0/21"
}

# RFC6598 range 100.64.0.0/10
# Note you can only /16 range to VPC. You can add multiples of /16 if required
variable "secondary_cidr_blocks" {
  description = "Secondary CIDR blocks to be attached to VPC"
  type        = list(string)
  default     = ["100.64.0.0/16"]
}

variable "enable_vpc_endpoints" {
  description = "Enable VPC Endpoints"
  type        = bool
  default     = false
}

variable "enable_yunikorn" {
  description = "Enable Apache YuniKorn Scheduler"
  type        = bool
  default     = false
}

variable "enable_amazon_prometheus" {
  description = "Enable AWS Managed Prometheus service"
  type        = bool
  default     = true
}

variable "enable_fsx_for_lustre" {
  description = "Deploys fsx for lustre addon, storage class and static FSx for Lustre filesystem for EMR"
  type        = bool
  default     = false
}

variable "enable_emr_spark_operator" {
  description = "Enable the Spark Operator to submit jobs with EMR Runtime"
  type        = bool
  default     = false
}

variable "enable_kubecost" {
  description = "Enable Kubecost add-on"
  type        = bool
  default     = true
}
