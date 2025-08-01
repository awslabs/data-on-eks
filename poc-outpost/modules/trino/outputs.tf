output "trino_data_bucket" {
  description = "Name of the S3 bucket to use for trino Data"
  value       = module.trino_s3_bucket.s3_bucket_id
}

output "trino_exchange_bucket" {
  description = "Name of the S3 bucket to use for trino Exchange Manager"
  value       = module.trino_exchange_bucket.s3_bucket_id
}

output "trino_user_password" {
  description = "Secret for Trino user"
  value       = random_password.trino_password.result
  sensitive = true
}

output "db" {
    description = "Database Trino"
    value       = module.db
}