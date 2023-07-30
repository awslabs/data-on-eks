#!/bin/bash

# Training Job Preparation & Launch
# Build the BERT pretraining and command shell container images and push them to ECR
# This job requires a docker folder(with assets folder with dump_env.py file) within the same directory as this script.

read -p "Did you install docker on AMD64(x86-64) machine (y/n): " response

if [[ "$response" == "N" || "$response" == "n" ]]; then
    echo -e "Please note that this job may encounter issues on ARM64 architecture. To proceed successfully, ensure that you have installed the Docker client and run it on AMD64 (x86-64) architecture. "
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

export DOCKER_BUILDKIT=1

# Build the Docker image and tag it with the ECR repository URI
echo -e "Building and Tagging Docker image... $ECR_REPO_URI:$IMAGE_TAG"
docker build ./docker -f docker/Dockerfile.bert_pretrain -t $ECR_REPO_URI:$IMAGE_TAG

# Login to ECR
echo -e "ECR Login with Docker..."
aws ecr get-login-password --region "$region" | docker login --username AWS --password-stdin "$ECR_REPO_URI"

# Push the Docker image to ECR
echo -e "Pushing Docker image..."
docker push "$ECR_REPO_URI:$IMAGE_TAG"

# Sleep for 5 seconds
echo -e "Sleeping for 5 seconds..."
sleep 5
