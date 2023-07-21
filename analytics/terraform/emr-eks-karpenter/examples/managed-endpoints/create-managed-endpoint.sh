#!/bin/bash

read -p "Enter EMR Virtual Cluster Id: " EMR_VIRTUAL_CLUSTER_ID
read -p "Provide your EMR on EKS team (emr-data-team-a or emr-data-team-b): " EMR_EKS_TEAM
read -p "Enter your AWS Region: " AWS_REGION
read -p "Enter a name for your endpoint: " EMR_EKS_MANAGED_ENDPOINT
read -p "Provide an S3 bucket location for logging (i.e. s3://my-bucket/logging/): " S3_BUCKET
read -p "Provide CloudWatch Logs Group Name: " CLOUDWATCH_LOGS_GROUP_NAME
read -p "Provide CloudWatch Logs Prefix: " CLOUDWATCH_LOGS_PREFIX
read -p "Enter the EMR Execution Role ARN (i.e. arn:aws:00000000000000000:role/EMR-Execution-Role): " EMR_EXECUTION_ROLE_ARN
read -p "Enter the release label (i.e. emr-6.9.0-latest): " EMR_EKS_RELEASE_LABEL

#-------------------------------------------------------
# Set Managed Endpoint JSON file with provided variables
#-------------------------------------------------------
export EMR_VIRTUAL_CLUSTER_ID=$EMR_VIRTUAL_CLUSTER_ID
export EMR_EKS_TEAM=$EMR_EKS_TEAM
export AWS_REGION=$AWS_REGION
export EMR_EKS_MANAGED_ENDPOINT=$EMR_EKS_MANAGED_ENDPOINT
export S3_BUCKET=$S3_BUCKET
export EMR_EXECUTION_ROLE_ARN=$EMR_EXECUTION_ROLE_ARN
export EMR_EKS_RELEASE_LABEL=$EMR_EKS_RELEASE_LABEL
export CLOUDWATCH_LOGS_GROUP_NAME=$CLOUDWATCH_LOGS_GROUP_NAME
export CLOUDWATCH_LOGS_PREFIX=$CLOUDWATCH_LOGS_PREFIX

envsubst < managed-endpoint.json > managed-endpoint-final.json

#------------------------------------------------------------------------------
# Create managed endpoint and assign Load Balancer information as env variables
#------------------------------------------------------------------------------

# Creating managed endpoint and saving the endpoint ID and Tag needed to identify the right Load Balancer
MANAGED_ENDPOINT_ID=$(aws emr-containers create-managed-endpoint --cli-input-json file://./managed-endpoint-final.json --query id --output text)
echo -e "The Managed Endpoint ID is $MANAGED_ENDPOINT_ID. \n"

TAG_VALUE=${EMR_EKS_TEAM}/ingress-${MANAGED_ENDPOINT_ID}

echo -e "Waiting for the managed endpoint load balancer to be active...\n"

sleep 30

# Saving Load Balancer ARN for the endpoint ingress
for i in $(aws elbv2 describe-load-balancers | jq -r '.LoadBalancers[].LoadBalancerArn'); do aws elbv2 describe-tags --resource-arns "$i" | jq -ce --arg TAG_VALUE $TAG_VALUE '.TagDescriptions[].Tags[] | select( .Key == "ingress.k8s.aws/stack" and .Value == $TAG_VALUE)' && ARN=$i ;done
echo -e "The Load Balancer ARN is $ARN. \n"

aws elbv2 wait load-balancer-available --load-balancer-arns $ARN

echo -e "The load balancer is in service. \n"

#------------------------------------------------------------------------
# Revise to add the Karpenter Security Group to the Load Balancer created
#------------------------------------------------------------------------

echo "Setting Security Groups for Jupyter Notebook and Karpenter..."
# Security Group for Endpoint with the Jupyter Notebook
NOTEBOOK_SG=$(aws ec2 describe-security-groups \
    --filters Name=group-name,Values="emr-containers-lb-$EMR_VIRTUAL_CLUSTER_ID-$MANAGED_ENDPOINT_ID" \
    --query "SecurityGroups[*].{ID:GroupId}" --output text)

# Karpenter Security Group
KARPENTER_SG=$(aws ec2 describe-security-groups \
    --filters Name=group-name,Values="emr-eks-karpenter-node-*" \
    --query "SecurityGroups[*].{ID:GroupId}" --output text)

echo "Adding the security groups to the load balancer..."
# Add these two Security Groups to the Load Balancer
RESULT=$(aws elbv2 set-security-groups --load-balancer-arn $ARN --security-groups $NOTEBOOK_SG $KARPENTER_SG)

# Wait for 30 seconds before the managed endpoint is ready.
sleep 30
echo "The managed endpoint has been created."
