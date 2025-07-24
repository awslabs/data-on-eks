export TRINO_BUCKET=$(aws s3 ls | grep trino-data | awk '{print $3}')
envsubst < trino_sf100000_tpcds_to_iceberg.sql > iceberg.sql

export dns=trino.orange-eks.com

echo "Get trino user password from terraform output"
cd ../.. && trino_user_password=$(terraform output -raw trino_user_password)
echo "use the folowing password: ${trino_user_password}"

cd -
echo "Running Trino query against Iceberg tables in S3 bucket: ${TRINO_BUCKET}"
trino --file 'iceberg.sql' --server "https://${dns}" --user trino --password --ignore-errors