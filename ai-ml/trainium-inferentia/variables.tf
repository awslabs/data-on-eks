variable "name" {
  description = "Name of the VPC and EKS Cluster"
  type        = string
  default     = "trainium-inferentia"
}

# NOTE: As of 2024/01/04 Trainium instances only available in us-west-2, us-east-1, and us-east-2 regions
#       Inferentia instances are available in the above regions + several others
variable "region" {
  description = "region"
  type        = string
  default     = "us-west-2"
}

variable "eks_cluster_version" {
  description = "EKS Cluster version"
  type        = string
  default     = "1.30"
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

variable "enable_jupyterhub" {
  description = "Enable JupyterHub deployment"
  type        = bool
  default     = false
}

variable "enable_mpi_operator" {
  description = "Flag to enable the MPI Operator deployment"
  type        = bool
  default     = false
}

variable "enable_volcano" {
  description = "Flag to enable the Volcano batch scheduler"
  type        = bool
  default     = false
}

variable "enable_torchx_etcd" {
  description = "Flag to enable etcd deployment for torchx"
  type        = bool
  default     = false
}

variable "enable_fsx_for_lustre" {
  description = "Flag to enable resources for FSx for Lustre"
  type        = bool
  default     = false
}

variable "trn1_32xl_min_size" {
  description = "trn1 Worker node minimum size"
  type        = number
  default     = 0
}

variable "trn1_32xl_desired_size" {
  description = "trn1 Worker node desired size"
  type        = number
  default     = 0
}

variable "trn1n_32xl_min_size" {
  description = "Worker node minimum size"
  type        = number
  default     = 0
}

variable "trn1n_32xl_desired_size" {
  description = "Worker node desired size"
  type        = number
  default     = 0
}

variable "inf2_24xl_min_size" {
  description = "Worker node minimum size"
  type        = number
  default     = 0
}

variable "inf2_24xl_desired_size" {
  description = "Worker node desired size"
  type        = number
  default     = 0
}

variable "inf2_48xl_min_size" {
  description = "Worker node minimum size"
  type        = number
  default     = 0
}

variable "inf2_48xl_desired_size" {
  description = "Worker node desired size"
  type        = number
  default     = 0
}

variable "enable_kuberay_operator" {
  description = "Flag to enable kuberay operator"
  type        = bool
  default     = true
}

variable "kms_key_admin_roles" {
  description = "list of role ARNs to add to the KMS policy"
  type        = list(string)
  default     = []
}

variable "enable_rayserve_ha_elastic_cache_redis" {
  description = "Flag to enable Ray Head High Availability with Elastic Cache for Redis"
  type        = bool
  default     = false
}
