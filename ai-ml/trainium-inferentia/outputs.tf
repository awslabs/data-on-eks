output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${var.region} update-kubeconfig --name ${local.name}"
}

output "elastic_cache_redis_cluster_arn" {
  description = "Cluster arn of the cache cluster"
  value       = module.elasticache.cluster_arn
}
