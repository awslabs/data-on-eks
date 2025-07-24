s3_bucket=$(aws s3 ls | awk '/airflow/ {print $3}')

aws s3 cp $1 s3://$s3_bucket/dags/$1

echo "file $1 copied to s3://$s3_bucket/dags/$1"
aws s3 ls s3://$s3_bucket/dags/