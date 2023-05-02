variable "name" {
  description = "Name of the EKS Cluster"
  default     = "emr-roadshow"
  type        = string
}

variable "region" {
  description = "region"
  type        = string
  default     = "us-east-1"
}

variable "eks_cluster_version" {
  description = "EKS Cluster version"
  default     = "1.24"
  type        = string
}

variable "tags" {
  description = "Default tags"
  default     = {}
  type        = map(string)
}

# variable "vpc_cidr" {
#   description = "VPC CIDR"
#   default     = "10.1.0.0/16"
#   type        = string
# }

# # Only two Subnets for with low IP range for internet access
# variable "public_subnets" {
#   description = "Public Subnets CIDRs. 62 IPs per Subnet"
#   default     = ["10.1.255.128/26", "10.1.255.192/26"]
#   type        = list(string)
# }

# variable "private_subnets" {
#   description = "Private Subnets CIDRs. 32766 Subnet1 and 16382 Subnet2 IPs per Subnet"
#   default     = ["10.1.0.0/17", "10.1.128.0/18"]
#   type        = list(string)
# }

variable "enable_yunikorn" {
  default     = false
  description = "Enable Apache YuniKorn Scheduler"
  type        = bool
}

variable "enable_fsx_for_lustre" {
  default     = false
  description = "Deploys fsx for lustre addon, storage class and static FSx for Lustre filesystem for EMR"
  type        = bool
}

variable "enable_cloudwatch_metrics" {
  default     = true
  description = "Enable Cloudwatch metrics"
  type        = bool
}

variable "enable_aws_for_fluentbit" {
  default     = false
  description = "Enable Fluentbit addon"
  type        = bool
}

variable "enable_grafana" {
  default     = false
  description = "Enable Open source Grafana addon"
  type        = bool
}
