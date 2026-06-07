#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "========================================="
echo " Starting Terraform Installation on Ubuntu"
echo "========================================="

# 1. Update system and install prerequisite tools
echo "--> Updating package lists and installing dependencies..."
sudo apt-get update && sudo apt-get install -y gnupg software-properties-common curl wget

# 2. Ensure the keyrings directory exists
echo "--> Preparing keyrings directory..."
sudo mkdir -p /etc/apt/keyrings

# 3. Download and install HashiCorp's official GPG key
echo "--> Adding HashiCorp GPG key..."
wget -O- https://apt.releases.hashicorp.com/gpg | \
  gpg --dearmor | \
  sudo tee /etc/apt/keyrings/hashicorp-archive-keyring.gpg > /dev/null

# 4. Add the official HashiCorp repository using the specific gpg keyring path
echo "--> Adding HashiCorp repository to sources.list.d..."
echo "deb [signed-by=/etc/apt/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list

# 5. Update repository index and install Terraform
echo "--> Updating package index with new repository..."
sudo apt-get update

echo "--> Installing Terraform..."
sudo apt-get install -y terraform

# 6. Verify installation
echo "========================================="
echo " Verification:"
terraform -version
echo "========================================="