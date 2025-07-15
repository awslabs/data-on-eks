# output "grafana_secret_name" {
#   value = aws_secretsmanager_secret.grafana.name
# }
#
# output "grafana_workspace_endpoint" {
#   description = "Amazon Managed Grafana Workspace endpoint"
#   value       = try("https://${module.managed_grafana[0].workspace_endpoint}", null)
# }