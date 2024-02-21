output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}"
}

output "data_bucket" {
  description = "Name of the S3 bucket to use for example Data"
  value       = module.trino_s3_bucket.s3_bucket_id
}
