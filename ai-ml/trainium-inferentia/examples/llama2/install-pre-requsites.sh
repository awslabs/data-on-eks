#!/bin/bash

# Function to install Docker
install_docker() {
    echo "Installing Docker..."
    sudo yum install docker -y
    sudo systemctl start docker
    sudo usermod -aG docker $(whoami)
    newgrp docker
}

# Check for Git
if ! command -v git &> /dev/null; then
    echo "Git is not installed. Installing..."
    sudo yum install git -y
else
    echo "Git is already installed."
fi

# Check for Kubectl
if ! command -v kubectl &> /dev/null; then
    echo "kubectl is not installed. Installing..."
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"
    echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check

    if [ $? -eq 0 ]; then
        echo "kubectl checksum is valid."
        sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
        kubectl version --client
    else
        echo "kubectl checksum is invalid. Installation aborted."
        exit 1
    fi
else
    echo "kubectl is already installed."
fi

# Check for AWS CLI v2
if ! command -v aws &> /dev/null || [[ ! $(aws --version) =~ "aws-cli/2" ]]; then
    echo "AWS CLI v2 is not installed. Installing..."
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
else
    echo "AWS CLI v2 is already installed."
fi

# Check for Docker
if ! command -v docker &> /dev/null; then
    install_docker
else
    echo "Docker is already installed."
fi

# Check for Terraform
if ! command -v terraform &> /dev/null; then
    echo "Terraform is not installed. Installing..."
    sudo yum install -y yum-utils
    sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
    sudo yum -y install terraform
else
    echo "Terraform is already installed."
fi
terraform -help

# Check for Helm
if ! command -v helm &> /dev/null; then
    echo "Helm is not installed. Installing..."
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
else
    echo "Helm is already installed."
fi

echo "Installation check complete."
