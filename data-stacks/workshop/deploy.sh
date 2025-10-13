#!/bin/bash

set -e

# Configuration
BLUEPRINT_NAME="spark-operator"
TERRAFORM_DIR="terraform"
AWS_REGION="${AWS_REGION:-us-east-1}"
KUBECONFIG_FILE="kubeconfig"
REPO_PATH=$(git rev-parse --show-toplevel)

source $REPO_PATH/infra/terraform/install-helpers.sh

print_status "Starting $BLUEPRINT_NAME deployment..."

check_prerequisites

# Generate random deployment_id if needed
# This ID is used to identify and delete AWS resources orphaned by Kubernetes Operators.
TFVARS_FILE="./terraform/blueprint.tfvars"
if [ -f "$TFVARS_FILE" ]; then
    if grep -q 'deployment_id = "abcdefg"' "$TFVARS_FILE"; then
        print_status "Default deployment_id found. Generating a new random one."
        RANDOM_ID=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 8)
        sed -i "s/deployment_id = \"abcdefg\"/deployment_id = \"$RANDOM_ID\"/" "$TFVARS_FILE"
        print_status "Updated deployment_id to $RANDOM_ID in $TFVARS_FILE"
    fi
else
    print_warning "$TFVARS_FILE not found. Skipping deployment_id update."
fi

# Clean up _local directory before copying files
if [ -d "./terraform/_local" ]; then
    print_status "Cleaning up terraform/_local directory..."
    find ./terraform/_local -mindepth 1 -maxdepth 1 -not -name '.terraform' -not -name '.terraform.lock.hcl' -not -name 'terraform.tfstate*' -exec rm -rf {} +
fi

# Copy base infrastructure files
print_status "Copying from the infra folder..."
mkdir -p ./terraform/_local
cp -r ../../infra/terraform/* ./terraform/_local/

# Apply blueprint files (overwriting matching files)
print_status "Overwriting files..."
tar -C ./terraform --exclude='_local' --exclude='*.tfstate*' --exclude='.terraform' -cf - . | tar -C ./terraform/_local -xvf -

cd terraform/_local
source ./install.sh
cp terraform.tfstate ../../terraform.tfstate.bak

cd ../..

setup_kubeconfig
export KUBECONFIG=$KUBECONFIG_FILE
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

print_next_steps