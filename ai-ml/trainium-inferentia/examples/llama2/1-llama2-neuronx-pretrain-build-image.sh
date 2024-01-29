#!/bin/bash

# Check that we are running on an x86_64 instance to avoid issues with docker build
arch=$(uname -m)
if [[ ! "$arch" = "x86_64" ]]; then
  echo "Error: please run this script on an x86_64-based instance"
  exit 1
fi

# Check if docker is installed
junk=$(which docker 2>&1 > /dev/null)
if [[ "$?" -ne 0 ]]; then
  echo "Error: please install docker and try again. ex: for AL2023 you can run:"
  echo "  sudo yum install docker -y"
  echo "  sudo systemctl start docker"
  echo "  sudo usermod -aG docker ec2-user"
  echo "  newgrp docker"
  exit 1
fi

# Check that AWS CLI is installed and configured
junk=$(aws sts get-caller-identity)
if [[ "$?" -ne 0 ]]; then
  echo "Error: please make sure that the AWS CLI is installed and configured using 'aws configure'."
  exit 1
fi

# Prompt user for desired region
read -p "Enter the ECR region: " region
echo $region > .eks_region

# Replace with your desired repository name
ECR_REPO_NAME="neuronx_nemo"

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

# Store ECR REPO URI for later use
echo $ECR_REPO_URI > .ecr_repo_uri

# Login to ECR
echo -e "\nLogging in to ECR"
aws ecr get-login-password --region "$region" | docker login --username AWS --password-stdin "$ECR_REPO_URI"

# Build neuronx-nemo-megatron docker image
echo -e "\nBuilding neuronx-nemo-megatron docker image"
docker build ./docker -f ./docker/Dockerfile.llama_pretrain -t $ECR_REPO_URI

# Push image to ECR
echo -e "\nPushing image to ECR"
docker push $ECR_REPO_URI:latest
