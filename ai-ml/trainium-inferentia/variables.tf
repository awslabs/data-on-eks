variable "name" {
  description = "Name of the VPC and EKS Cluster"
  default     = "trn1-inf2"
  type        = string
}

# NOTE: As of 2024/01/04 Trainium instances only available in us-west-2, us-east-1, and us-east-2 regions
#       Inferentia instances are available in the above regions + several others
variable "region" {
  description = "region"
  default     = "us-west-2"
  type        = string
}

variable "eks_cluster_version" {
  description = "EKS Cluster version"
  default     = "1.28"
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

variable "enable_amazon_prometheus" {
  description = "Enable AWS Managed Prometheus service"
  type        = bool
  default     = true
}

variable "mpi_operator_version" {
  description = "The version of the MPI Operator to install"
  default     = "v0.4.0"
  type        = string
}

variable "enable_mpi_operator" {
  description = "Flag to enable the MPI Operator deployment"
  type        = bool
  default     = false
}

variable "min_size" {
  description = "Worker node minimum size"
  type = number
  default = 0
}

variable "max_size" {
  description = "Worker node max size"
  type = number
  default = 0
}

variable "desired_size" {
  description = "Worker node desired size"
  type = number
  default = 0
}