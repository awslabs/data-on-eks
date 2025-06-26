# output "configure_kubectl" {
#   description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
#   value       = "aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}"
# }

# output "grafana_secret_name" {
#   description = "Grafana password secret name"
#   value       = aws_secretsmanager_secret.grafana.name
# }
output "eks_cluster_certificate_authority_data" {
  value = module.eks.cluster_certificate_authority_data
  description = "Le certificat CA utilisé par le serveur API EKS"
  sensitive = true
}

output "eks_cluster_endpoint" {
  value       = module.eks.cluster_endpoint
  description = "Le endpoint du cluster EKS"
}

output "eks_cluster_name" {
  value       = module.eks.cluster_name
  description = "Nom du cluster EKS"
}