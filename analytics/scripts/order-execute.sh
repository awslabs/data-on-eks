#!/bin/bash
# This job copies Sample PySpark script and some test data to your S3 Directory bucket which will enable you to run Spark Operator scripts

# Prerequisites for running this shell script
#     1/ Execute the Python script generate-order-data.py to generate order.parquet input file
#     2/ Execute the shell script with the required arguments
#         ./your_script.sh <S3_DIRECTORY_BUCKET> <REGION>
#     3/ Ensure <S3_DIRECTORY_BUCKET> is replaced in "spark-app-*.yaml" files
#     4/ Execute the shell script which creates the input data in your S3 Directory bucket
#     5/ Run `kubectl apply -f spark-app-*.yaml` to trigger the Spark job
#     6/ Monitor the Spark job using "kubectl get pods -n spark-s3-express -w"

# Script usage ./order-execute my-s3-directory-bucket us-west-2

if [ $# -ne 2 ]; then
  echo "Usage: $0 <S3_DIRECTORY_BUCKET> <REGION>"
  exit 1
fi

S3_DIRECTORY_BUCKET="$1"
REGION="$2"

INPUT_DATA_S3_PATH="s3://${S3_DIRECTORY_BUCKET}/order/input"

# Copy PySpark Script to S3 bucket
aws s3api put-object --bucket ${S3_DIRECTORY_BUCKET} --key scripts/pyspark-order.py --body pyspark-order.py --region ${REGION}

# Copy Test Input data to S3 bucket
aws s3api put-object --bucket ${S3_DIRECTORY_BUCKET} --key order/input/order1.parquet --body order.parquet --region ${REGION}
aws s3api put-object --bucket ${S3_DIRECTORY_BUCKET} --key order/input/order2.parquet --body order.parquet --region ${REGION}
aws s3api put-object --bucket ${S3_DIRECTORY_BUCKET} --key order/input/order3.parquet --body order.parquet --region ${REGION}
aws s3api put-object --bucket ${S3_DIRECTORY_BUCKET} --key order/input/order4.parquet --body order.parquet --region ${REGION}
