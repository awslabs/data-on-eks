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
output "grafana_secret_name" {
  description = "Grafana password secret name"
  value       = aws_secretsmanager_secret.grafana.name
}

output "emr_s3_bucket_name" {
  description = "S3 bucket for EMR workloads. Scripts,Logs etc."
  value       = module.s3_bucket.s3_bucket_id
}

output "fsx_s3_bucket_name" {
  description = "FSx filesystem sync with S3 bucket"
  value       = try(module.fsx_s3_bucket.s3_bucket_id, null)
}

output "aws_region" {
  description = "AWS Region"
  value       = local.region
}
