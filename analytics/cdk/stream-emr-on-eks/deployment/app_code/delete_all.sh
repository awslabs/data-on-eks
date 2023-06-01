#!/bin/bash

export stack_name="${1:-emr-stream-demo}"

# delete EMR virtual cluster if needed
emr_cv=$(aws emr-containers list-virtual-clusters --state ARRESTED --query 'virtualClusters[*].id' --output text)
if [ ! -z "$emr_cv" ]; then
    for i in emr_cv; do
        aws emr-containers delete-virtual-cluster --id $i
    done
fi

# delete S3
S3BUCKET=$(aws cloudformation describe-stacks --stack-name $stack_name --query "Stacks[0].Outputs[?OutputKey=='CODEBUCKET'].OutputValue" --output text)
if [ ! "$S3BUCKET" == 'None' ]; then
    echo "Delete EMR log from S3"
    aws s3 rm s3://$S3BUCKET --recursive
    aws s3 rb s3://$S3BUCKET --force
fi

# delete the rest from CF
echo "Delete the rest of resources by CloudFormation delete command"
aws cloudformation delete-stack --stack-name $stack_name
