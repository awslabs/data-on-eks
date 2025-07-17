# output "configure_kubectl" {
#   description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
#   value       = "aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}"
# }

# output "grafana_secret_name" {
#   description = "Grafana password secret name"
#   value       = aws_secretsmanager_secret.grafana.name
# }
output "eks_cluster_certificate_authority_data" {
  value       = module.eks.cluster_certificate_authority_data
  description = "Le certificat CA utilisé par le serveur API EKS"
  sensitive   = true
}

output "eks_cluster_endpoint" {
  value       = module.eks.cluster_endpoint
  description = "Le endpoint du cluster EKS"
}

output "eks_cluster_name" {
  value       = module.eks.cluster_name
  description = "Nom du cluster EKS"
}

output "S3_airflow_data_bucket" {
  value       = length(module.airflow) > 0 ? module.airflow[0].airflow_data_bucket : null
  description = "Le bucket S3 utilisé par airflow pour les dags et les logs"
}

output "S3_trino_data_bucket" {
  value       = length(module.trino) > 0 ? module.trino[0].trino_data_bucket : null
  description = "Le bucket S3 utilisé par Trino pour stocker les données"
}

output "wiledcard_certificate_arn" {
  value       = module.utility.wildcard_certificate_arn
  description = "ARN du certificat wildcard utilisé pour le domaine principal"
}