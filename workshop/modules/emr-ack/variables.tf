variable "helm_config" {
  description = "EMR ACK Controller Helm Chart values"
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

variable "ecr_public_repository_username" {
  description = "ECR Public repository Username for Helm Charts"
  type        = string
}

variable "ecr_public_repository_password" {
  description = "ECR Public repository Password for Helm Charts"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all AWS resources"
  type        = map(string)
  default     = {}
}
