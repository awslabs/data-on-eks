#!/bin/bash

# Install Terraform v1.2.8
TERRAFORM_VERSION="1.2.8"
TERRAFORM_ZIP="terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
curl -O "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/${TERRAFORM_ZIP}"
sudo unzip $TERRAFORM_ZIP -d /usr/local/bin/
rm $TERRAFORM_ZIP

# Install kubectl
sudo curl --silent --location -o /usr/local/bin/kubectl "https://dl.k8s.io/release/$(curl --silent --location https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo chmod +x /usr/local/bin/kubectl

# Install Helm
sudo curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash

# Add official Helm repository
helm repo add stable https://charts.helm.sh/stable

# Update Helm repository
helm repo update

# Verify Helm installation
helm version

curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Clone repo
git clone https://github.com/awslabs/data-on-eks.git