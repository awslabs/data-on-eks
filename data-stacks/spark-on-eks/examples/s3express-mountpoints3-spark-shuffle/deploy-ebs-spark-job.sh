#!/bin/bash

set -e

echo "Spark EBS Job Deployment"

# Get inputs
read -p "S3 bucket name for data/logs: " S3_BUCKET
read -p "Availability zone: " AVAILABILITY_ZONE

# Create temporary file with substituted values
TEMP_FILE=$(mktemp)
trap "rm -f $TEMP_FILE" EXIT

# Substitute placeholders and deploy
sed -e "s/S3_BUCKET_PLACEHOLDER/$S3_BUCKET/g" \
    -e "s/AVAILABILITY_ZONE_PLACEHOLDER/$AVAILABILITY_ZONE/g" \
    ebs-shuffle-example.yaml > "$TEMP_FILE"

kubectl apply -f "$TEMP_FILE"

echo "Spark EBS job submitted!"