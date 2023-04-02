output "spark_operator" {
  value       = try(helm_release.spark_operator[0].metadata, null)
  description = "Spark Operator Helm Chart metadata"
}

output "yunikorn" {
  value       = try(helm_release.yunikorn[0].metadata, null)
  description = "Yunikorn Helm Chart metadata"
}

output "prometheus" {
  value       = try(helm_release.prometheus[0].metadata, null)
  description = "Prometheus Helm Chart metadata"
}

output "kubecost" {
  value       = try(helm_release.kubecost[0].metadata, null)
  description = "Kubecost Helm Chart metadata"
}

output "spark_history_server" {
  value       = try(helm_release.spark_history_server[0].metadata, null)
  description = "Spark History Server Helm Chart metadata"
}
