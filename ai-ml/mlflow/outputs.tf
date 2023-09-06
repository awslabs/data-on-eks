output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}"
}

output "eks_api_server_url" {
  description = "Your eks API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "grafana_secret_name" {
  description = "Grafana password secret name"
  value       = aws_secretsmanager_secret.grafana.name
}

output "mlflow_s3_artifacts" {
  description = "S3 bucket for MLflow artifacts"
  value = module.mlflow_s3_bucket[0].s3_bucket_id
}

output "mlflow_db_backend" {
  description = "Amazon RDS Postgres database for MLflow backend"
  value = module.db[0].db_instance_endpoint
}