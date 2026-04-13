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
# S3 Files Configuration
################################################################################

output "s3_files_filesystem_id" {
  description = "S3 Files filesystem ID - use this in PersistentVolume manifests"
  value       = aws_s3files_file_system.spark_data.id
}

output "s3_files_filesystem_arn" {
  description = "S3 Files filesystem ARN"
  value       = aws_s3files_file_system.spark_data.arn
}

output "s3_files_access_point_id" {
  description = "S3 Files Access Point ID for spark-team-a"
  value       = aws_s3files_access_point.spark_team_a.id
}

output "s3_files_access_point_arn" {
  description = "S3 Files Access Point ARN for spark-team-a"
  value       = aws_s3files_access_point.spark_team_a.arn
}

output "s3_files_mount_targets" {
  description = "S3 Files mount target IDs by AZ"
  value       = { for idx, mt in aws_s3files_mount_target.spark_data : local.azs[idx] => mt.id }
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
