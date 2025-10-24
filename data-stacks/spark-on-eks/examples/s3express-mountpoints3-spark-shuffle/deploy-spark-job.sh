#!/bin/bash

set -e

echo "Spark S3 Express Job Deployment"

# Get inputs
read -p "S3 bucket name for data/logs: " S3_BUCKET
read -p "Availability zone: " AVAILABILITY_ZONE

# Create temporary file with substituted values
TEMP_FILE=$(mktemp)
trap "rm -f $TEMP_FILE" EXIT

# Substitute placeholders and deploy
sed -e "s/S3_BUCKET_PLACEHOLDER/$S3_BUCKET/g" \
    -e "s/AVAILABILITY_ZONE_PLACEHOLDER/$AVAILABILITY_ZONE/g" \
    s3express-shuffle-example.yaml > "$TEMP_FILE"

kubectl apply -f "$TEMP_FILE"

echo "Spark job submitted!"