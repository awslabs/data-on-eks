export dns=trinoalb4.orange-eks.com

echo "Get trino user password from terraform output"
cd ../.. && trino_user_password=$(terraform output -raw trino_user_password)
echo "use the folowing password: ${trino_user_password}"

cd -
echo "Running Trino query select multiple tables in Iceberg"
trino --file 'trino_select_query_iceberg.sql' --server "https://${dns}" --user trino --password --ignore-errors