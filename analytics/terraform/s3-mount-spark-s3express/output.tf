output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}"
}

output "s3express_bucket_name" {
  description = "s3express bucket name"
  value       = aws_s3_directory_bucket.spark_data_bucket_express.id
}

output "s3express_bucket_zone" {
  description = "s3express bucket availability zone"
  value       = local.s3_express_zone_name
}

output "az_names" {
  description = "s3express bucket availability zone"
  value       = local.azs
}

output "az_ids" {
  description = "s3express bucket availability zone"
  value       = local.az_ids
}

output "grafana_secret_name" {
  description = "Secret name for Grafana access"
  value       = "${local.name}-grafana"
}