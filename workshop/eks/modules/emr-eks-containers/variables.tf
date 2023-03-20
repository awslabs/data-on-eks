variable "emr_on_eks_config" {
  description = "EMR on EKS Helm configuration values"
  type        = any
  default     = {}
}

variable "eks_cluster_id" {
  description = "Name of the EKS Cluster"
  type        = string
}

variable "eks_oidc_provider_arn" {
  description = "The OpenID Connect identity provider ARN"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all AWS resources"
  type        = map(string)
  default     = {}
}
