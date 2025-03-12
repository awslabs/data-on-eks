variable "name" {
  description = "Name of the VPC and EKS Cluster"
  default     = "jark-stack"
  type        = string
}

# NOTE: Trainium and Inferentia are only available in us-west-2 and us-east-1 regions
variable "region" {
  description = "region"
  default     = "us-west-2"
  type        = string
}

variable "eks_cluster_version" {
  description = "EKS Cluster version"
  default     = "1.30"
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

variable "huggingface_token" {
  description = "Hugging Face Secret Token"
  type        = string
  default     = "DUMMY_TOKEN_REPLACE_ME"
  sensitive   = true
}

variable "enable_aws_efa_k8s_device_plugin" {
  description = "Enable AWS EFA K8s Device Plugin"
  type        = bool
  default     = false
}

variable "enable_kubecost" {
  description = "Enable Kubecost addon"
  type        = bool
  default     = false
}


variable "bottlerocket_data_disk_snpashot_id" {
  description = "Bottlerocket Data Disk Snapshot ID"
  type        = string
  default     = ""

}
