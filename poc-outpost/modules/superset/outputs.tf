# output "cluster_address" {
#   description = "(Memcached only) DNS name of the cache cluster without the port appended"
#   value       = try(module.elasticache.cluster_address, null)
# }
#
# output "cluster_configuration_endpoint" {
#   description = "(Memcached only) Configuration endpoint to allow host discovery"
#   value       = try(module.elasticache.cluster_configuration_endpoint, null)
# }

output "debug" {
  value = module.elasticache
}