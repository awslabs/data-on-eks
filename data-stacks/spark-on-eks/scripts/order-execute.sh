#!/bin/bash
# Copies the sample PySpark script and order data to your S3 Directory bucket for the spark-app-*.yaml examples.
# Before you run this script, create the order.parquet input file in this folder.
# Usage: ./order-execute.sh <S3_DIRECTORY_BUCKET> <REGION>
# Then replace <S3_DIRECTORY_BUCKET> in the spark-app-*.yaml files and run `kubectl apply -f spark-app-<name>.yaml`.

if [ $# -ne 2 ]; then
  echo "Usage: $0 <S3_DIRECTORY_BUCKET> <REGION>"
  exit 1
fi

S3_DIRECTORY_BUCKET="$1"
REGION="$2"

INPUT_DATA_S3_PATH="s3://${S3_DIRECTORY_BUCKET}/order/input"

aws s3api put-object --bucket ${S3_DIRECTORY_BUCKET} --key scripts/pyspark-order.py --body pyspark-order.py --region ${REGION}

aws s3api put-object --bucket ${S3_DIRECTORY_BUCKET} --key order/input/order1.parquet --body order.parquet --region ${REGION}
aws s3api put-object --bucket ${S3_DIRECTORY_BUCKET} --key order/input/order2.parquet --body order.parquet --region ${REGION}
aws s3api put-object --bucket ${S3_DIRECTORY_BUCKET} --key order/input/order3.parquet --body order.parquet --region ${REGION}
aws s3api put-object --bucket ${S3_DIRECTORY_BUCKET} --key order/input/order4.parquet --body order.parquet --region ${REGION}
