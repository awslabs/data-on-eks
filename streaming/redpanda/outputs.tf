################################################################################
# Cluster
################################################################################
output "cluster_arn" {
  description = "The Amazon Resource Name (ARN) of the cluster"
  value       = module.eks.cluster_arn
}

output "cluster_name" {
  description = "The Amazon Resource Name (ARN) of the cluster"
  value       = module.eks.cluster_id
}

output "oidc_provider" {
  description = "The OIDC Provider"
  value       = module.eks.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "The ARN of the OIDC Provider"
  value       = module.eks.oidc_provider_arn
}

################################################################################
# VPC Info
################################################################################
output "vpc_id" {
  description = "Map of attribute maps for all EKS managed node groups created"
  value       = module.vpc.vpc_id
}
output "vpc_subnets" {
  description = "Map of attribute maps for all EKS managed node groups created"
  value       = module.vpc.public_subnets
}
################################################################################
# Kubernetes Config
################################################################################

output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}"
}

