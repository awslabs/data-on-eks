#!/bin/bash
set -o errexit
set -o pipefail

read -p "Enter the EMR Virtual Cluster ID: " EMR_VIRTUAL_CLUSTER_ID
read -p "Enter the EMR Execution Role ARN: " EMR_EXECUTION_ROLE_ARN
read -p "Enter the CloudWatch Log Group name: " CLOUDWATCH_LOG_GROUP

aws emr-containers start-job-run \
   --virtual-cluster-id $EMR_VIRTUAL_CLUSTER_ID \
   --name=pi \
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
           }
       }
   }'
