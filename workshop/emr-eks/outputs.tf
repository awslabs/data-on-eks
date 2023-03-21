output "vpc_id" {
  description = "The ID of the VPC"
  value       = try(module.vpc_workshop[0].vpc_id, null)
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = try(module.vpc_workshop[0].vpc_cidr_block, null)
}

output "public_subnets" {
  description = "List of IDs of public subnets"
  value       = try(module.vpc_workshop[0].public_subnets, null)
}

output "public_subnets_cidr_blocks" {
  description = "List of cidr_blocks of public subnets"
  value       = try(module.vpc_workshop[0].public_subnets_cidr_blocks, null)
}

output "private_subnets" {
  description = "List of IDs of private subnets"
  value       = try(module.vpc_workshop[0].private_subnets, null)
}

output "private_subnets_cidr_blocks" {
  description = "List of cidr_blocks of private subnets"
  value       = try(module.vpc_workshop[0].private_subnets_cidr_blocks, null)
}

#--------------------------------------------------------
################################################################################
# Cluster
################################################################################
output "cluster_arn" {
  description = "The Amazon Resource Name (ARN) of the cluster"
  value       = try(module.eks_workshop[0].cluster_arn, null)
}

output "cluster_name" {
  description = "EKS Cluster name"
  value       = try(module.eks_workshop[0].cluster_name, var.cluster_name)
}

output "cluster_endpoint" {
  description = "EKS Clusetr endpoint"
  value       = try(module.eks_workshop[0].cluster_endpoint, var.cluster_endpoint)
}

output "oidc_provider_arn" {
  description = "The ARN of the OIDC Provider if `enable_irsa = true`"
  value       = try(module.eks_workshop[0].oidc_provider_arn, var.oidc_provider_arn)
}

output "oidc_provider" {
  description = "The OIDC Provider if `enable_irsa = true`"
  value       = try(module.eks_workshop[0].oidc_provider, var.oidc_provider)
}

output "cluster_certificate_authority_data" {
  description = "EKS CLuster certificate authority data"
  value       = try(module.eks_workshop[0].cluster_certificate_authority_data, null)
}

################################################################################
# EKS Managed Node Group
################################################################################
output "eks_managed_node_groups" {
  description = "Map of attribute maps for all EKS managed node groups created"
  value       = try(module.eks_workshop[0].eks_managed_node_groups, null)
}

output "eks_managed_node_groups_iam_role_name" {
  description = "List of the autoscaling group names created by EKS managed node groups"
  value       = try(compact(flatten([for group in module.eks_workshop[0].eks_managed_node_groups : group.iam_role_name])), null)
}

output "aws_auth_configmap_yaml" {
  description = "Formatted yaml output for base aws-auth configmap containing roles used in cluster node groups/fargate profiles"
  value       = try(module.eks_workshop[0].aws_auth_configmap_yaml, null)
}

output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${var.region} update-kubeconfig --name ${var.cluster_name}"
}

output "emr_on_eks" {
  description = "EMR on EKS"
  value       = module.emr_containers_workshop
}

output "s3_bucket_name" {
  description = "EMR on EKS"
  value       = module.s3_bucket.s3_bucket_id
}
