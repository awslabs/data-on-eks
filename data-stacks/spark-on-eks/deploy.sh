#!/bin/bash

set -e

# --- Configuration ---
STACKS="spark-operator"
TERRAFORM_DIR="terraform"
AWS_REGION="${AWS_REGION:-us-east-1}"
KUBECONFIG_FILE="kubeconfig.yaml"


# --- Get Repo Root ---
REPO_PATH=$(git rev-parse --show-toplevel)

# --- Source and Execute the Main Deployment Engine ---
# The centralized install.sh handles all the heavy lifting.
source $REPO_PATH/infra/terraform/install.sh

# --- Post-Deployment Steps ---
# Steps specific to this stack can be added here.
print_status "Running stack-specific post-deployment steps..."

# Backup the state file from the _local directory
cp "$TERRAFORM_DIR/_local/terraform.tfstate" "$TERRAFORM_DIR/terraform.tfstate.bak"
print_status "Backed up terraform.tfstate."

# Setup kubeconfig
setup_kubeconfig

# Get ArgoCD admin password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

print_next_steps
