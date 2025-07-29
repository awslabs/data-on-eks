# output "configure_kubectl" {
#   description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
#   value       = "aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}"
#   # aws eks update-kubeconfig --region us-west-2 --name poc-orange-doeks
#   # aws eks update-kubeconfig --region us-west-2 --name poc-orange-doeks-otl4
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

output "grafana_local_secret_name" {
  value       = module.supervision.grafana_secret_name
  description = "Le nom du secret contenant le mot de passe admin de Grafana pour permettre de récupérer le mot de passe admin de Grafana"
}

output "airflow_admin_password" {
  value       = length(module.airflow) > 0 ? module.airflow[0].airflow_admin_password : null
  description = "Le mot de passe admin de Airflow"
  sensitive   = true
}

output "trino_user_password" {
  value       = length(module.trino) > 0 ? module.trino[0].trino_user_password : null
  description = "Le mot de passe pour l'utilisateur Trino"
  sensitive   = true
}


output "s3_bucket_id_spark_history_server" {
  description = "Spark History server logs S3 bucket ID"
  value       = length(module.spark-operator) > 0 ? module.spark-operator[0].s3_bucket_id_spark_history_server : null
}