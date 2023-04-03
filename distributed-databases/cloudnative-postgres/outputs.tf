output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}"
}

output "barman_backup_irsa" {
  description = "ARN for Backup IAM ROLE"
  value       = module.barman_backup_irsa.irsa_iam_role_arn

}

output "barman_s3_bucket" {
  description = "Backup bucket"
  value       = module.barman_s3_bucket.s3_bucket_id
}
