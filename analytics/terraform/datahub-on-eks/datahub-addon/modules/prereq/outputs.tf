################################################################################
# Prerequisites outputs for ES, MSK, RDS
################################################################################
output "es_endpoint" {
  description = "ElasticSearch Cluster Endpoint"
  value       = aws_opensearch_domain.es.endpoint
}

output "msk_bootstrap_brokers" {
  description = "MSK bootstrap_brokers"
  value       = aws_msk_cluster.msk.bootstrap_brokers
}

output "msk_zookeeper_connect_string" {
  description = "MSK zookeeper connect_string"
  value       = aws_msk_cluster.msk.zookeeper_connect_string
}

output "rds_address" {
  description = "RDS address"
  value       = aws_db_instance.datahub_rds.address
}

output "rds_endpoint" {
  description = "RDS host"
  value       = aws_db_instance.datahub_rds.endpoint
}

output "rds_password" {
  value = random_password.mysql_password.result
}

output "es_password" {
  value = random_password.master_password.result
}
