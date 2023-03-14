#!/bin/bash
set -o errexit
set -o pipefail

read -p "Enter EMR Virtual Cluster AWS Region: " AWS_REGION
read -p "Enter the EMR Virtual Cluster ID: " EMR_VIRTUAL_CLUSTER_ID
read -p "Enter the EMR Execution Role ARN: " EMR_EXECUTION_ROLE_ARN
read -p "Enter the CloudWatch Log Group name: " CLOUDWATCH_LOG_GROUP
read -p "Enter the CloudWatch Log Group name(e.g., s3://my-bucket-name ): " S3_BUCKET_LOGS

aws emr-containers start-job-run \
   --virtual-cluster-id $EMR_VIRTUAL_CLUSTER_ID \
   --name=pi \
   --region $AWS_REGION \
   --execution-role-arn $EMR_EXECUTION_ROLE_ARN \
   --release-label emr-6.8.0-latest \
   --job-driver '{
       "sparkSubmitJobDriver":{
               "entryPoint": "local:///usr/lib/spark/examples/src/main/python/pi.py",
               "sparkSubmitParameters": "--conf spark.executor.instances=2 --conf spark.executor.memory=2G --conf spark.executor.cores=2 --conf spark.driver.cores=1"
       }
   }' \
   --configuration-overrides '{
       "monitoringConfiguration": {
           "persistentAppUI": "ENABLED",
           "cloudWatchMonitoringConfiguration": {
               "logGroupName": "'"${CLOUDWATCH_LOG_GROUP}"'",
               "logStreamNamePrefix": "sample-pi"
           },
           "s3MonitoringConfiguration": {
               "logUri": "'"${S3_BUCKET_LOGS}/"'"
           }
       }
   }'
