output "datahub_admin_password" {
  description = "The generated password for the default datahub admin user"
  value       = random_password.datahub_user_password.result
  sensitive   = true
}

output "datahub_namespace" {
  description = "The Kubernetes namespace where DataHub is deployed"
  value       = local.datahub_namespace
}
