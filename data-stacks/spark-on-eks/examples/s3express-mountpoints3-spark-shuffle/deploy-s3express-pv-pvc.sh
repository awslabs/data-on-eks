#!/bin/bash

set -e

echo "S3 Express PV/PVC Deployment"

# Get inputs
read -p "S3 Express bucket name: " BUCKET_NAME
read -p "AWS region: " REGION
read -p "Availability zone: " AVAILABILITY_ZONE

# Create namespace if it doesn't exist
kubectl create namespace spark-s3-express --dry-run=client -o yaml | kubectl apply -f -

# Create temporary file with substituted values
TEMP_FILE=$(mktemp)
trap "rm -f $TEMP_FILE" EXIT

# Substitute placeholders and deploy
sed -e "s/BUCKET_NAME_PLACEHOLDER/$BUCKET_NAME/g" \
    -e "s/REGION_PLACEHOLDER/$REGION/g" \
    -e "s/AVAILABILITY_ZONE_PLACEHOLDER/$AVAILABILITY_ZONE/g" \
    s3express-pv-pvc.yaml > "$TEMP_FILE"

kubectl apply -f "$TEMP_FILE"

echo "Deployment complete!"