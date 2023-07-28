#!/bin/bash

# 1. Training Job Preparation & Launch
# 1.1 Build the BERT pretraining and command shell container images and push them to ECR

read -p "Did you inntall docker (y/n): " response

if [[ "$response" == "N" || "$response" == "n" ]]; then
    echo -e "Please install Podman before proceeding. Install it from here: https://podman.io/."
    exit 0
fi

read -p "Enter the ECR region: " region

# Replace with your desired repository name and region
ECR_REPO_NAME="eks_torchx_test"
IMAGE_TAG="bert_pretrain"

# Check if the ECR repository exists
if aws ecr describe-repositories --repository-names "$ECR_REPO_NAME" --region "$region" >/dev/null 2>&1; then
  echo "ECR repository '$ECR_REPO_NAME' already exists."

  # Get the ECR_REPO_URI for the existing repository
  ECR_REPO_URI=$(aws ecr describe-repositories --repository-name "$ECR_REPO_NAME" --query 'repositories[0].repositoryUri' --region "$region" --output text)
  echo "Repository URL: $ECR_REPO_URI"
else
  # Create the ECR repository
  aws ecr create-repository --repository-name "$ECR_REPO_NAME" --region "$region"

  # Get the ECR_REPO_URI for the newly created repository
  ECR_REPO_URI=$(aws ecr describe-repositories --repository-name "$ECR_REPO_NAME" --query 'repositories[0].repositoryUri' --region "$region" --output text)
  echo "ECR repository '$ECR_REPO_NAME' created successfully."
  echo "Repository URL: $ECR_REPO_URI"
fi

# Building Docker image
echo -e "Building Docker image... $ECR_REPO_URI:$IMAGE_TAG"
docker build --tag "$ECR_REPO_URI:$IMAGE_TAG" --file Dockerfile.bert_pretrain .

# Tagging the Docker image
echo -e "Tagging Docker image... $ECR_REPO_URI:$IMAGE_TAG"
docker tag "$ECR_REPO_URI:$IMAGE_TAG" "$ECR_REPO_URI:$IMAGE_TAG"

# Login to ECR
echo -e "ECR Login with Docker..."
aws ecr get-login-password --region "$region" | docker login --username AWS --password-stdin "$ECR_REPO_URI"

# Push the Docker image to ECR
echo -e "Pushing Docker image..."
docker push "$ECR_REPO_URI:$IMAGE_TAG"

# Sleep for 5 seconds
echo -e "Sleeping for 5 seconds..."
sleep 5
