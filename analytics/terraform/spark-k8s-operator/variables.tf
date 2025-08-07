variable "name" {
  description = "Name of the VPC and EKS Cluster"
  default     = "spark-on-eks"
  type        = string
}

variable "region" {
  description = "Region"
  type        = string
  default     = "us-west-2"
}

variable "eks_cluster_version" {
  description = "EKS Cluster version"
  default     = "1.33"
  type        = string
}

# VPC
variable "vpc_cidr" {
  description = "VPC CIDR. This should be a valid private (RFC 1918) CIDR range"
  default     = "10.1.0.0/16"
  type        = string
}

# RFC6598 range 100.64.0.0/10
# Note you can only /16 range to VPC. You can add multiples of /16 if required
variable "secondary_cidr_blocks" {
  description = "Secondary CIDR blocks to be attached to VPC"
  default     = ["100.64.0.0/16"]
  type        = list(string)
}

# Enable this for fully private clusters
variable "enable_vpc_endpoints" {
  description = "Enable VPC Endpoints"
  default     = false
  type        = bool
}

variable "enable_amazon_prometheus" {
  description = "Enable AWS Managed Prometheus service"
  type        = bool
  default     = true
}

variable "enable_yunikorn" {
  default     = false
  description = "Enable Apache YuniKorn Scheduler"
  type        = bool
}

variable "enable_jupyterhub" {
  default     = false
  description = "Enable Jupyter Hub"
  type        = bool
}

variable "kms_key_admin_roles" {
  description = "list of role ARNs to add to the KMS policy"
  type        = list(string)
  default     = []
}

variable "spark_benchmark_ssd_min_size" {
  description = "Minimum size for nodegroup of c5d 12xlarge instances to run data generation for Spark benchmark"
  type        = number
  default     = 0
}

variable "spark_benchmark_ssd_desired_size" {
  description = "Desired size for nodegroup of c5d 12xlarge instances to run data generation for Spark benchmark"
  type        = number
  default     = 0
}

variable "enable_raydata" {
  description = "Enable Ray Data Spark logs processing with Iceberg"
  type        = bool
  default     = false
}
