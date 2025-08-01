output "airflow_data_bucket" {
description = "Name of the S3 bucket to use for airflow Data"
value       = module.airflow_s3_bucket.s3_bucket_id
}
output "airflow_admin_password" {
  value     = random_password.airflow_admin.result
  sensitive = true
}
output "db" {
  description = "Database Airflow"
  value       = module.db
}