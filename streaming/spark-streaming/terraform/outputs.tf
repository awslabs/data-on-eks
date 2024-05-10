################################################################################
# Cluster
################################################################################

output "cluster_arn" {
  description = "The Amazon Resource Name (ARN) of the cluster"
  value       = module.eks.cluster_arn
}

output "cluster_name" {
  description = "The Amazon Resource Name (ARN) of the cluster"
  value       = var.name
}

output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}"
}

################################################################################
# Private Subnets
################################################################################

output "subnet_ids_starting_with_100" {
  description = "Secondary CIDR Private Subnet IDs for EKS Data Plane"
  value       = compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) : substr(cidr_block, 0, 4) == "100." ? subnet_id : null])
}

output "s3_bucket_id_spark_history_server" {
  description = "Spark History server logs S3 bucket ID"
  value       = module.s3_bucket.s3_bucket_id
}

output "s3_bucket_region_spark_history_server" {
  description = "Spark History server logs S3 bucket ID"
  value       = module.s3_bucket.s3_bucket_region
}

output "grafana_secret_name" {
  description = "Grafana password secret name"
  value       = aws_secretsmanager_secret.grafana.name
}

################################################################################
# MSK Outputs
################################################################################

output "bootstrap_brokers" {
  description = "Bootstrap brokers for the MSK cluster"
  value       = aws_msk_cluster.kafka_test_demo.bootstrap_brokers
}

################################################################################
# Application Related Outputs
################################################################################

output "s3_bucket_id_iceberg_bucket" {
  description = "Spark History server logs S3 bucket ID"
  value       = aws_s3_bucket.iceberg_data.id
}

output "producer_iam_role_arn" {
  description = "IAM role ARN for the producer"
  value       = module.producer_iam_role.iam_role_arn
}

output "consumer_iam_role_arn" {
  description = "IAM role ARN for the consumer"
  value       = module.spark_team_a_irsa.iam_role_arn
}
