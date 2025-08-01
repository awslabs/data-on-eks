output "s3_bucket_id_spark_history_server" {
  description = "Spark History server logs S3 bucket ID"
  value       = module.s3_bucket.s3_bucket_id
}
output "test" {
    description = "Test output to verify module execution"
    value       =  module.spark_history_server_irsa.iam_role_arn
}