#!/bin/bash

cd terraform/_local
export S3_BUCKET=$(terraform output -raw emr_s3_bucket_name)
export AWS_REGION=$(terraform output -raw region)
export CLUSTER_NAME=$(terraform output -raw cluster_name)

# Export EMR Virtual Cluster details
export EMR_VIRTUAL_CLUSTER_ID_TEAM_A=$(terraform output -json emr_on_eks | jq -r '."emr-data-team-a".virtual_cluster_id')
export EMR_EXECUTION_ROLE_ARN_TEAM_A=$(terraform output -json emr_on_eks | jq -r '."emr-data-team-a".job_execution_role_arn')
export CLOUDWATCH_LOG_GROUP_TEAM_A=$(terraform output -json emr_on_eks | jq -r '."emr-data-team-a".cloudwatch_log_group_name')

export EMR_VIRTUAL_CLUSTER_ID_TEAM_B=$(terraform output -json emr_on_eks | jq -r '."emr-data-team-b".virtual_cluster_id')
export EMR_EXECUTION_ROLE_ARN_TEAM_B=$(terraform output -json emr_on_eks | jq -r '."emr-data-team-b".job_execution_role_arn')
export CLOUDWATCH_LOG_GROUP_TEAM_B=$(terraform output -json emr_on_eks | jq -r '."emr-data-team-b".cloudwatch_log_group_name')

cd -

echo "Environment variables set:"
echo "  S3_BUCKET=$S3_BUCKET"
echo "  AWS_REGION=$AWS_REGION"
echo "  CLUSTER_NAME=$CLUSTER_NAME"
echo "  EMR_VIRTUAL_CLUSTER_ID_TEAM_A=$EMR_VIRTUAL_CLUSTER_ID_TEAM_A"
echo "  EMR_EXECUTION_ROLE_ARN_TEAM_A=$EMR_EXECUTION_ROLE_ARN_TEAM_A"
