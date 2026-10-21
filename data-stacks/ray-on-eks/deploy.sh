#!/bin/bash

set -e

# --- Configuration ---
STACKS="ray-on-eks"
TERRAFORM_DIR="terraform"
AWS_REGION="${AWS_REGION:-us-west-2}"
KUBECONFIG_FILE="kubeconfig.yaml"


# --- Remote Terraform state (optional) ---
# If this AWS account has a bucket named terraform-state-<account>-<region>,
# keep this stack's state there (s3://<bucket>/ray-on-eks/terraform.tfstate),
# so the stack can be managed from more than one machine. Without that bucket,
# state stays local in terraform/_local as before. Override with TF_STATE_BUCKET.
if [[ -z "${TF_STATE_BUCKET:-}" ]]; then
  _state_bucket="terraform-state-$(aws sts get-caller-identity --query Account --output text)-${AWS_REGION}"
  if aws s3api head-bucket --bucket "$_state_bucket" >/dev/null 2>&1; then
    export TF_STATE_BUCKET="$_state_bucket"
  fi
fi

# --- Get Repo Root ---
REPO_PATH=$(git rev-parse --show-toplevel)

# --- Source and Execute the Main Deployment Engine ---
# The centralized install.sh handles all the heavy lifting.
source $REPO_PATH/infra/terraform/install.sh

# --- Post-Deployment Steps ---
# Steps specific to this stack can be added here.
print_status "Running stack-specific post-deployment steps..."

# Backup the state file from the _local directory (local state only; with
# remote state the S3 bucket's versioning is the backup).
if [[ -z "${TF_STATE_BUCKET:-}" && -f "$TERRAFORM_DIR/_local/terraform.tfstate" ]]; then
  cp "$TERRAFORM_DIR/_local/terraform.tfstate" "$TERRAFORM_DIR/terraform.tfstate.bak"
  print_status "Backed up terraform.tfstate."
fi

# Setup kubeconfig
setup_kubeconfig

# Get ArgoCD admin password
export KUBECONFIG=$KUBECONFIG_FILE
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

print_next_steps
