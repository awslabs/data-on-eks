# =============================================================================
# Outputs
# =============================================================================

output "iam_role_arn" {
  description = "ARN of the IAM role for IRSA"
  value       = aws_iam_role.ray_s3_access.arn
}

output "iam_role_name" {
  description = "Name of the IAM role"
  value       = aws_iam_role.ray_s3_access.name
}

output "iam_policy_arn" {
  description = "ARN of the S3 and Glue access policy"
  value       = aws_iam_policy.s3_access.arn
}

output "iam_policy_name" {
  description = "Name of the S3 and Glue access policy"
  value       = aws_iam_policy.s3_access.name
}

output "ray_config" {
  description = "Ray configuration values"
  value       = local.ray_config
}

output "glue_database_name" {
  description = "Name of the AWS Glue database for Iceberg"
  value       = aws_glue_catalog_database.raydata_iceberg.name
}

output "namespace" {
  description = "Kubernetes namespace for Ray Data workloads"
  value       = var.namespace
}

output "service_account_name" {
  description = "Kubernetes service account name"
  value       = var.service_account_name
}

output "iceberg_warehouse_path" {
  description = "S3 path for Iceberg warehouse"
  value       = "s3://${var.s3_bucket}/iceberg-warehouse/"
}

output "service_account_arn" {
  description = "IAM role ARN attached to the service account"
  value       = aws_iam_role.ray_s3_access.arn
}

output "deployment_instructions" {
  description = "Instructions for deploying the Ray job"
  value       = <<-EOT
    Ray Data infrastructure deployed successfully!
    
    IAM Role: ${aws_iam_role.ray_s3_access.arn}
    Service Account: ${var.service_account_name} in namespace ${var.namespace}
    
    To deploy the Ray job:
    1. cd examples/raydata-sparklogs-processing-job
    2. Update S3_BUCKET in execute-rayjob.sh to: ${var.s3_bucket}
    3. ./execute-rayjob.sh deploy
  EOT
}