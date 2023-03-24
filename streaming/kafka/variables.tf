variable "name" {
  description = "Name of the VPC and EKS Cluster"
  type        = string
  default     = "kafka-on-eks"
}

variable "region" {
  description = "region"
  type        = string
  default     = "us-west-2"
}

variable "eks_cluster_version" {
  description = "EKS Cluster version"
  type        = string
  default     = "1.24"
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable "k8ssandra_helm_config"{
  description = "Helm provider config for the k8ssandra-operator."
  type        = any
  default     = {}
}

# variable "addon_context" {
#   description = "Input configuration for the addon"
#   type = object({
#     aws_caller_identity_account_id = string
#     aws_caller_identity_arn        = string
#     aws_eks_cluster_endpoint       = string
#     aws_partition_id               = string
#     aws_region_name                = string
#     eks_cluster_id                 = string
#     eks_oidc_issuer_url            = string
#     eks_oidc_provider_arn          = string
#     tags                           = map(string)
#     irsa_iam_role_path             = string
#     irsa_iam_permissions_boundary  = string
#   })
# }

