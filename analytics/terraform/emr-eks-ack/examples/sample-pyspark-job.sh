#!/bin/bash

# Prompt the user for the required values
read -p "Enter the CloudWatch log group name: " cloudwatch_log_group
read -p "Enter the EMR execution role ARN: " emr_execution_role_arn

# Generate a random ID using the date and time
random_id=$(date +%s)

# Replace the placeholders in the YAML file with the user-provided values
sed -i "s/\${CLOUDWATCH_LOG_GROUP}/$cloudwatch_log_group/g" sample-pyspark-job.yaml
sed -i "s/\${RANDOM_ID}/$random_id/g" my-jobrun.yaml
sed -i "s/\${EMR_EXECUTION_ROLE_ARN}/$emr_execution_role_arn/g" sample-pyspark-job.yaml

# Apply the modified YAML file with kubectl
kubectl apply -f sample-pyspark-job.yaml
