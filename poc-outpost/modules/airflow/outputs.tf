output "airflow_data_bucket" {
description = "Name of the S3 bucket to use for airflow Data"
value       = module.airflow_s3_bucket[0].s3_bucket_id
}