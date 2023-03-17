variable "cluster_name" {
  type        = string
  description = "EKS Cluster name"
  default     = null
}

variable "tags" {
  description = "Default tags"
  default     = {}
  type        = map(string)
}

variable "vpc_id" {
  description = "VPC ID"
  default     = null
  type        = string
}

variable "private_subnet" {
  type        = string
  description = "Private Subnet Fsx for Lustre file system"
  default     = null
}

variable "private_subnets_cidr_blocks" {
  description = "VPC Private Subnet CIDR Blocks"
  default     = []
  type        = list(string)
}
