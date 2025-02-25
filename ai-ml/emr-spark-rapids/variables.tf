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
  default     = "1.31"
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

variable "enable_amazon_prometheus" {
  description = "Enable AWS Managed Prometheus service"
  default     = true
  type        = bool
}

variable "enable_nvidia_gpu_operator" {
  description = "Enable NVIDIA GPU Operator"
  default     = false
  type        = bool
}

variable "kms_key_admin_roles" {
  description = "list of role ARNs to add to the KMS policy"
  type        = list(string)
  default     = []
}
