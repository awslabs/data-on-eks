

export S3_BUCKET=$(terraform -chdir=terraform output -raw s3_bucket_id_spark_history_server)
export S3_DIRECTORY_BUCKET=$(terraform -chdir=terraform output -raw s3directory_bucket_name)
