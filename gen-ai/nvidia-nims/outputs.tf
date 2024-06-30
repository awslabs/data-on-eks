output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${var.region} update-kubeconfig --name ${var.name}"
}

# output "s3_bucket_name" {
#   description = "The name of the S3 bucket."
#   value       = module.s3_bucket.s3_bucket_id
# }

# output "s3_bucket_region" {
#   description = "The AWS region this bucket resides in."
#   value       = module.s3_bucket.s3_bucket_region
# }

output "grafana_secret_name" {
  description = "The name of the secret containing the Grafana admin password."
  value       = aws_secretsmanager_secret.grafana.name
}
