#s3_bucket=$(aws s3 ls | awk '/airflow/ {print $3}')
#aws s3 cp $1 s3://$s3_bucket/dags/$1

kubectl -n airflow-s3-user cp "$1" \
$(kubectl get pod -l app=client-awscli -n airflow-s3-user -o jsonpath="{.items[0].metadata.name}"):/data-to-upload/
echo "file $1 to be uploaded to S3 bucket airflow"
#aws s3 ls s3://$s3_bucket/dags/
