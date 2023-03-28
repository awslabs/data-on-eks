#!/bin/bash

# NOTE: Make sure to set the region before running the shell script e.g., export AWS_REGION="<your-region>"

read -p "Enter the AWS Region: " AWS_REGION
read -p "Enter the S3 Bucket created for storing PySpark Scripts, and Input data. For e.g., s3://<bucket-name>: " S3_BUCKET
read -p "Enter the ARN of the Step Function created: " STATE_MACHINE_ARN

aws s3 cp s3://aws-data-analytics-workshops/emr-eks-workshop/scripts/spark-etl.py "${S3_BUCKET}/scripts/"
aws s3 sync s3://aws-data-analytics-workshops/shared_datasets/tripdata/ "${S3_BUCKET}/shared_datasets/tripdata/"


aws stepfunctions start-execution --state-machine-arn $STATE_MACHINE_ARN  --region $AWS_REGION 
