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

output "oidc_provider_arn" {
  description = "The ARN of the OIDC Provider if `enable_irsa = true`"
  value       = module.eks.oidc_provider_arn
}

################################################################################
# EKS Managed Node Group
################################################################################

output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}"
}

output "emr_on_eks" {
  description = "EMR on EKS"
  value       = module.emr_containers
}

################################################################################
# AMP
################################################################################

output "amp_workspace_id" {
  description = "The id of amp"
  value       = aws_prometheus_workspace.amp[0].id
}

output "grafana_secret_name" {
  description = "Grafana password secret name"
  value       = aws_secretsmanager_secret.grafana.name
}

output "s3_bucket_id" {
  description = "S3 bucket for Spark input and output data"
  value       = module.s3_bucket.s3_bucket_id
}
