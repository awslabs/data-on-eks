#!/bin/bash

# Function to install Docker
install_docker() {
    echo "Checking and installing Docker..."
    sudo yum install docker -y
    sudo systemctl start docker
    sudo usermod -aG docker $(whoami)
    newgrp docker
}

# Install a package if it is not already installed
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

echo "Starting installation of prerequisites..."

# Install Docker
install_docker

# Install Git, Python3, unzip, pip, and jq
install_package git
install_package python3
install_package unzip
install_package python3-pip
install_package jq

# Additional installations (kubectl, AWS CLI v2, Terraform, Helm, Boto3)...
# (Include the existing logic for these installations here, with similar echo statements for tracking)

echo "Installation of prerequisites complete."
