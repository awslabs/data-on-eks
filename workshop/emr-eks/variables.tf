variable "name" {
  description = "Name of the VPC"
  default     = "doeks-workshop"
  type        = string
}

variable "region" {
  description = "region"
  type        = string
  default     = "us-west-2"
}

variable "tags" {
  description = "Default tags"
  default     = {}
  type        = map(string)
}

#-------------------------------------------------------
# VPC Module variables
#-------------------------------------------------------
variable "create_vpc" {
  description = "Enable VPC module"
  default     = true
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  default     = "10.1.0.0/16"
  type        = string
}

variable "public_subnets" {
  description = "Public Subnets CIDRs. 62 IPs per Subnet"
  default     = ["10.1.255.128/26", "10.1.255.192/26"]
  type        = list(string)
}

variable "private_subnets" {
  description = "Private Subnets CIDRs. 32766 Subnet1 and 16382 Subnet2 IPs per Subnet"
  default     = ["10.1.0.0/17", "10.1.128.0/18"]
  type        = list(string)
}

#-------------------------------------------------------
# Update this to use existing VPC and private subnets and change `create_vpc = false`
#-------------------------------------------------------
variable "vpc_id" {
  description = "VPC Id"
  default     = null
  type        = string
}

variable "private_subnet_ids" {
  description = "Private Subnet IDs"
  default     = null
  type        = list(string)
}

#-------------------------------------------------------
# EKS Module variables
#-------------------------------------------------------
variable "create_eks" {
  description = "Enable EKS module"
  default     = true
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "doeks-workshop"
}

variable "cluster_version" {
  description = "EKS Cluster version"
  default     = "1.24"
  type        = string
}

#-------------------------------------------------------
# Update this section for existing EKS CLuster to be used and change create_eks=false
#-------------------------------------------------------
variable "cluster_endpoint" {
  description = "Endpoint for your Kubernetes API server"
  type        = string
  default     = null
}

variable "oidc_provider" {
  description = "The OpenID Connect identity provider (issuer URL without leading `https://`)"
  type        = string
  default     = null
}

variable "oidc_provider_arn" {
  description = "The ARN of the cluster OIDC Provider"
  type        = string
  default     = null
}

variable "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  type        = string
  default     = null
}

variable "karpenter_iam_instance_profile_name" {
  description = "Karpenter IAM instance profile name"
  type        = string
  default     = null
}

#-------------------------------------------------------
# EKS Addons
#-------------------------------------------------------
variable "enable_karpenter" {
  description = "Enable Karpenter autoscaler add-on"
  type        = bool
  default     = true
}

variable "enable_yunikorn" {
  default     = false
  description = "Enable Apache YuniKorn Scheduler"
  type        = bool
}

variable "enable_kubecost" {
  description = "Enable Kubecost add-on"
  type        = bool
  default     = true
}

variable "enable_grafana" {
  description = "Enable Grafana add-on"
  type        = bool
  default     = false
}

variable "enable_cloudwatch_metrics" {
  description = "Enable AWS Cloudwatch Metrics add-on for Container Insights"
  type        = bool
  default     = true
}

variable "enable_aws_for_fluentbit" {
  description = "Enable AWS for FluentBit add-on"
  type        = bool
  default     = true
}

variable "enable_amazon_prometheus" {
  description = "Enable AWS Managed Prometheus service"
  type        = bool
  default     = true
}

variable "enable_prometheus" {
  description = "Enable Community Prometheus add-on"
  type        = bool
  default     = true
}

variable "enable_aws_fsx_csi_driver" {
  description = "Enable AWS FSx CSI driver add-on"
  type        = bool
  default     = false
}

#-------------------------------------------------------
# EMR ACK Controller module
#-------------------------------------------------------
variable "enable_emr_ack_controller" {
  description = "Enable EMR ACK Controller"
  default     = false
  type        = string
}
