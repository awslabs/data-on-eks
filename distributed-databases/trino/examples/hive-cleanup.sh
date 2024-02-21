#!/bin/bash

export AWS_REGION=$(terraform output --state="../terraform.tfstate" --raw configure_kubectl | awk '{ print $4 }')
export BUCKET=$(terraform output --state="../terraform.tfstate" --raw data_bucket)
export ACCOUNT_ID=$(aws sts get-caller-identity | jq -r .Account)
export GLUE_TABLE_NANE=hive
export GLUE_DB_NAME=taxi_hive_database
export CRAWLER_NAME=taxi-data-crawler

## Delete the Glue Database, Crawler, and Table generated
aws glue delete-table --database-name $GLUE_DB_NAME --name $GLUE_TABLE_NAME --region $AWS_REGION --no-paginate
echo "Table deleted."
aws glue delete-crawler --name $CRAWLER_NAME --region $AWS_REGION --no-paginate
echo "Crawler deleted."
aws glue delete-database --name $GLUE_DB_NAME --region $AWS_REGION --no-paginate
echo "Glue Database deleted."

## Delete IAM resources created for the example
aws iam detach-role-policy --role-name AWSGlueServiceRole-test-hive --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole --no-paginate
aws iam delete-role-policy --role-name AWSGlueServiceRole-test-hive --policy-name glue-s3-policy --no-paginate
aws iam delete-role --role-name AWSGlueServiceRole-test-hive --no-paginate
echo "Glue IAM role deleted."

## Empty the bucket
aws s3 rm s3://$BUCKET --recursive
echo "S3 Data Bucket is now empty."
