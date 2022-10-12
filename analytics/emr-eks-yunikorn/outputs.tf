output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = module.eks_blueprints.configure_kubectl
}

output "emrcontainers_virtual_cluster_id" {
  description = "EMR Containers Virtual cluster ID"
  value       = { for cluster in sort(keys(local.emr_on_eks_teams)) : cluster => aws_emrcontainers_virtual_cluster.this[cluster].id }
}

output "emrcontainers_virtual_cluster_name" {
  description = "EMR Containers Virtual cluster ID"
  value       = { for cluster in sort(keys(local.emr_on_eks_teams)) : cluster => aws_emrcontainers_virtual_cluster.this[cluster].name }
}

output "emr_on_eks_role_id" {
  description = "IAM execution role ID for EMR on EKS"
  value       = module.eks_blueprints.emr_on_eks_role_id
}

output "emr_on_eks_role_arn" {
  description = "IAM execution role arn for EMR on EKS"
  value       = module.eks_blueprints.emr_on_eks_role_arn
}
