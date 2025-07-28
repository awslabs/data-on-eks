cd ../.. && trino_bucket=$(terraform output -raw S3_trino_data_bucket)
cd -
export TRINO_BUCKET="${trino_bucket}"
envsubst < trino_sf100000_tpcds_to_iceberg.sql > iceberg.sql

export dns=trinoalb4.orange-eks.com

echo "Get trino user password from terraform output"
cd ../.. && trino_user_password=$(terraform output -raw trino_user_password)
echo "use the folowing password: ${trino_user_password}"

cd -
echo "Running Trino query against Iceberg tables in S3 bucket: ${TRINO_BUCKET}"
trino --file 'iceberg.sql' --server "https://${dns}" --user trino --password --ignore-errors