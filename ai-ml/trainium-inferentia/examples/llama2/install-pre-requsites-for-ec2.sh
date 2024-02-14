#!/bin/bash

# Function to install Docker
install_docker() {
    echo "Checking and installing Docker..."
    sudo yum install docker -y
    sudo service docker start
    sudo usermod -aG docker $(whoami)
    # newgrp docker removed to prevent script interruption
}

# Function to install a package using yum
install_package() {
    PACKAGE=$1
    echo "Checking for $PACKAGE..."
    if ! command -v $PACKAGE &> /dev/null; then
        echo "Installing $PACKAGE..."
        sudo yum install $PACKAGE -y
    else
        echo "$PACKAGE is already installed."
    fi
}

# Function to install kubectl
install_kubectl() {
    echo "Installing kubectl..."
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
}

# Function to install Terraform
install_terraform() {
    echo "Installing Terraform..."
    sudo yum install -y yum-utils
    sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
    sudo yum install -y terraform
}

# Function to install AWS CLI v2
install_aws_cli() {
    echo "Installing AWS CLI v2..."
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
    echo "AWS CLI v2 installed successfully."
}

# Function to install Helm
install_helm() {
    echo "Installing Helm..."
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    echo "Helm installed successfully."
}

# Function to install Boto3
install_boto3() {
    echo "Installing Boto3..."
    pip3 install boto3
    echo "Boto3 installed successfully."
}

echo "Starting installation of prerequisites..."

# Install Docker
install_docker

# Install Git, Python3, unzip, pip, and jq
install_package git
install_package python3
install_package unzip
install_package python3-pip
install_package jq

# Install kubectl, Terraform, AWS CLI v2, Helm, and Boto3
install_kubectl
install_terraform
install_aws_cli
install_helm
install_boto3

echo "Installation of prerequisites complete."
