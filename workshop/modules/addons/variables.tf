variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_endpoint" {
  description = "Endpoint for your Kubernetes API server"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes `<major>.<minor>` version to use for the EKS cluster (i.e.: `1.24`)"
  type        = string
}

variable "oidc_provider" {
  description = "The OpenID Connect identity provider (issuer URL without leading `https://`)"
  type        = string
}

variable "oidc_provider_arn" {
  description = "The ARN of the cluster OIDC Provider"
  type        = string
}

variable "region" {
  description = "region"
  type        = string
  default     = "us-west-2"
}

variable "karpenter_iam_instance_profile_name" {
  description = "Karpenter IAM instance profile name"
  type        = string
}

variable "ecr_repository_username" {
  description = "ECR public repository username"
  type        = string
}

variable "ecr_repository_password" {
  description = "ECR public repository password"
  type        = string
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

variable "enable_yunikorn" {
  default     = false
  description = "Enable Apache YuniKorn Scheduler"
  type        = bool
}

variable "enable_kubecost" {
  default     = true
  description = "Enable KubeCost addon"
  type        = bool
}
