variable "name" {
  description = "Name of the VPC and EKS Cluster"
  default     = "doeks-workshop"
  type        = string
}

variable "region" {
  description = "region"
  type        = string
  default     = "us-west-2"
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  default     = "10.1.0.0/16"
  type        = string
}

# Only two Subnets for with low IP range for internet access
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
