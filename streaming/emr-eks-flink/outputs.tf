# create output for flink operator role arn
output "flink_jobs_role_arn" {
  value       = trimspace(module.flink_irsa_jobs.iam_role_arn)
  description = "IAM linked role for the flink job"
}
output "flink_operator_role_arn" {
  value       = module.flink_irsa_operator.iam_role_arn
  description = "IAM linked role for the flink operator"
}

output "flink_checkpoint_path" {
  value       = "s3://${module.s3_bucket.s3_bucket_id}/checkpoints"
  description = "S3 path for checkpoint data"
}
output "flink_savepoint_path" {
  value       = "s3://${module.s3_bucket.s3_bucket_id}/savepoints"
  description = "S3 path for savepoint data"
}
output "flink_jobmanager_path" {
  value       = "s3://${module.s3_bucket.s3_bucket_id}/jobmanager"
  description = "S3 path for jobmanager data"
}

output "flink_logs_path" {
  value       = "s3://${module.s3_bucket.s3_bucket_id}/logs"
  description = "S3 path for logs"
}
