#!/bin/bash

# Set the AWS region and the name of the ECR repository

REGION=us-west-2
ECR_REPO_NAME=jupyterhub-pytorch-neuron-pytorch
DOCKER_FILE=docker/jupyterhub-pytorch-neuron-pytorch.Dockerfile

# Check if the ECR repository exists
if aws ecr describe-repositories --repository-names "$ECR_REPO_NAME" --region "$REGION" >/dev/null 2>&1; then
  echo "ECR repository '$ECR_REPO_NAME' already exists."

  # Get the ECR_REPO_URI for the existing repository
  ECR_REPO_URI=$(aws ecr describe-repositories --repository-name "$ECR_REPO_NAME" --query 'repositories[0].repositoryUri' --region "$REGION" --output text)
  echo "Repository URL: $ECR_REPO_URI"
else
    # Create a new ECR repository with the specified name and region
    aws ecr create-repository --repository-name "$ECR_REPO_NAME" --region "$REGION"

    # Retrieve the URL of the newly created ECR repository
    ECR_REPO_URI=$(aws ecr describe-repositories --repository-name "$ECR_REPO_NAME" --query 'repositories[0].repositoryUri' --region "$REGION" --output text)
    echo "Repository URL: $ECR_REPO_URI"
fi

# Log in to Amazon ECR using docker
echo -e "Logging in to Amazon ECR..."
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$ECR_REPO_URI"

# Build the docker image using the provided jupyterhub-pytorch-neuron.Dockerfile and tag it with the ECR repository URI
echo -e "Building, tagging and pushing docker image... $ECR_REPO_URI:latest"
# docker build -f docker/jupyterhub-pytorch-neuron.Dockerfile-jupterhub-inferentia-pytorch -t "$ECR_REPO_URI:latest" .
docker buildx build --push --tag "$ECR_REPO_URI:latest" -o type=image --platform=linux/amd64 -f $DOCKER_FILE .

# Wait for 5 seconds
sleep 5
echo -e "Sleeping for 5 seconds..."
