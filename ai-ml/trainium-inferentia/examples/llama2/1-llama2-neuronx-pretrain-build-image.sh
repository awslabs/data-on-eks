#!/bin/bash

# Set strict error handling
set -euo pipefail

# Environment Variables
AWS_ACCOUNT_ID="123255318457"
AWS_REGION="us-west-2"
ECR_REPO_NAME="neuronx_nemo"
FSX_PATH="fs-08515da32c3dbe2ef"
# Add other necessary environment variables here

# Function to Clone the NeuronX-Nemo-Megatron Repository
clone_repo() {
    echo "Checking if the NeuronX-Nemo-Megatron repository already exists..."
    if [ -d "neuronx-nemo-megatron" ]; then
        echo "The NeuronX-Nemo-Megatron repository already exists. Skipping cloning."
    else
        echo "Cloning the NeuronX-Nemo-Megatron repository..."
        if ! git clone https://github.com/aws-neuron/neuronx-nemo-megatron.git; then
            echo "Error cloning repository"
            exit 1
        fi
    fi
}


# Function to Install Prerequisites
install_prereqs() {
    echo "Installing prerequisites..."
    if ! pip3 install torch --index-url https://download.pytorch.org/whl/cpu; then
        echo "Error installing PyTorch"
        exit 1
    fi
    if ! pip3 install wheel; then
        echo "Error installing Wheel"
        exit 1
    fi
    # Add other installation commands here
}

# Function to Modify Configuration Files
modify_files() {
    echo "Modifying configuration files..."
    local test_llama_path="./neuronx-nemo-megatron/nemo/examples/nlp/language_modeling/test_llama.sh"

    # Cross-platform sed in-place edit: Using '' for macOS, -i for Linux
    if [[ "$OSTYPE" == "darwin"* ]]; then
        SED_CMD="sed -i ''"
    else
        SED_CMD="sed -i"
    fi

    if ! $SED_CMD 's|old_tokenizer_path|new_tokenizer_path|g' "$test_llama_path"; then
        echo "Error modifying $test_llama_path"
        exit 1
    fi
    if ! $SED_CMD 's|old_dataset_path|new_dataset_path|g' "$test_llama_path"; then
        echo "Error modifying $test_llama_path"
        exit 1
    fi
    # Add other file modifications here
}


# Function to Build Docker Image and Push to ECR
build_and_push_docker() {
    echo "Building Docker image and pushing to ECR..."

    # Change to the neuronx-nemo-megatron directory
    if [[ -d "neuronx-nemo-megatron" ]]; then
        cd neuronx-nemo-megatron
    else
        echo "neuronx-nemo-megatron directory not found. Exiting."
        exit 1
    fi

    # Check for build.sh in the neuronx-nemo-megatron directory
    if [[ ! -f "build.sh" ]]; then
        echo "build.sh not found in the neuronx-nemo-megatron directory. Exiting."
        exit 1
    fi

    # Enable Docker BuildKit for better performance
    export DOCKER_BUILDKIT=1

    # Build the Nemo and Apex wheels
    echo "Building Nemo and Apex wheels..."
    ./build.sh || { echo "Failed to build Nemo and Apex wheels"; exit 1; }

    # AWS / ECR / Repo Info
    AWS_ACCT=$(aws sts get-caller-identity | jq -r ".Account") || { echo "Failed to get AWS account"; exit 1; }
    REGION=us-west-2
    ECR_REPO=$AWS_ACCT.dkr.ecr.$REGION.amazonaws.com/neuronx_nemo

    # Authenticate with ECR
    echo "Logging into AWS ECR..."
    aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $AWS_ACCT.dkr.ecr.$REGION.amazonaws.com || { echo "Failed to login to AWS ECR"; exit 1; }

    # Build and push the image
    echo "Building and pushing the Docker image to ECR..."
    docker build . -f ./k8s/docker/Dockerfile -t $ECR_REPO:latest || { echo "Docker build failed"; exit 1; }
    docker push $ECR_REPO:latest || { echo "Failed to push Docker image to ECR"; exit 1; }

    echo "Docker image successfully built and pushed to ECR."
}








# Function to Set Up Kubernetes
setup_kubernetes() {
    echo "Setting up Kubernetes..."
    if ! kubectl apply -f ./k8s/example_manifests/mpi_compile_llama7b.yaml; then
        echo "Error applying mpi_compile_llama7b.yaml"
        exit 1
    fi
    if ! kubectl apply -f ./k8s/example_manifests/mpi_train_llama7b.yaml; then
        echo "Error applying mpi_train_llama7b.yaml"
        exit 1
    fi
    # Add other Kubernetes setup commands here
}

# Main Execution Flow
echo "Starting the installation and setup process..."

clone_repo
install_prereqs
modify_files
build_and_push_docker
setup_kubernetes

echo "Installation and setup completed successfully."
