################################################################################
# Cluster
################################################################################

output "cluster_arn" {
  description = "The Amazon Resource Name (ARN) of the cluster"
  value       = module.eks.cluster_arn
}

output "cluster_name" {
  description = "The Amazon Resource Name (ARN) of the cluster"
  value       = module.eks.cluster_name
}

output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}"
}

output "node_iam_role_name" {
  description = "EKS Auto node IAM role name"
  value       = module.eks.node_iam_role_name
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
# S3 Directory Bucket
################################################################################


output "s3directory_bucket_name" {
  description = "s3 directory bucket name"
  value       = aws_s3_directory_bucket.spark_data_bucket_express.bucket
}

output "s3directory_bucket_region" {
  description = "s3 directory bucket region"
  value       = local.region
}

output "s3directory_bucket_zone" {
  description = "s3 directory bucket availability zone"
  value       = local.s3_express_zone_name
}

################################################################################
# Ray Data Configuration
################################################################################

output "raydata_config" {
  description = "Configuration for Ray Data processing"
  value = var.enable_raydata ? {
    namespace         = "raydata"
    service_account   = "raydata" # Created by spark-team.tf
    s3_prefix         = local.s3_prefix
    iceberg_database  = local.iceberg_database
    iceberg_warehouse = "s3://${module.s3_bucket.s3_bucket_id}/iceberg-warehouse/"
    iam_role_arn      = module.spark_team_irsa["raydata"].iam_role_arn
  } : null
}

################################################################################
# ECR
################################################################################

output "ecr_repo_url" {
  description = "ECR repository URL for Spot Balancer image"
  value       = aws_ecr_repository.spot_balancer.repository_url
# Celeborn Configuration
################################################################################

output "celeborn_master_endpoint" {
  description = "Celeborn master endpoint for Spark shuffle configuration"
  value       = var.enable_celeborn ? "celeborn-master-0.celeborn-master-svc.celeborn.svc.cluster.local:9097" : null
}
