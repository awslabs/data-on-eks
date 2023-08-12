#!/bin/bash

# Set the AWS region and the name of the ECR repository
REGION=us-west-2
ECR_REPO_NAME=eks_mlperf_training

# Create a new ECR repository with the specified name and region
aws ecr create-repository --repository-name "$ECR_REPO_NAME" --region "$REGION"

# Retrieve the URL of the newly created ECR repository
ECR_REPO_URI=$(aws ecr describe-repositories --repository-name "$ECR_REPO_NAME" --query 'repositories[0].repositoryUri' --region "$REGION" --output text)
echo "Repository URL: $ECR_REPO_URI"

# Build the podman image using the provided podmanfile and tag it with the ECR repository URI
echo -e "Building and tagging podman image... $ECR_REPO_URI:mlp"
podman build -f podmanfile -t "$ECR_REPO_URI:mlp" .

# Log in to Amazon ECR using podman
echo -e "Logging in to Amazon ECR..."
aws ecr get-login-password --region "$REGION" | podman login --username AWS --password-stdin "$ECR_REPO_URI"

# Push the podman image to the ECR repository
echo -e "Pushing podman image..."
podman push "$ECR_REPO_URI:mlp"

# Wait for 5 seconds
sleep 5
echo -e "Sleeping for 5 seconds..."
