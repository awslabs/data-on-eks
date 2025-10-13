#!/bin/bash

set -e

# This script is the centralized deployment engine.
# It's intended to be called from a blueprint's deploy.sh script.

# --- Path and Prerequisite Setup ---
REPO_PATH=$(git rev-parse --show-toplevel)
STACKS_DIR=$(pwd)
ORIGINAL_DIR=$(pwd) # Save the original directory
source $REPO_PATH/infra/terraform/install-helpers.sh

print_status "Starting deployment engine from: $STACKS_DIR"
check_prerequisites

# --- Configuration Validation ---
# Expects TERRAFORM_DIR to be set by the calling script.
TERRAFORM_DIR="${TERRAFORM_DIR:-terraform}" # Default to 'terraform' if not set
LOCAL_DIR="$STACKS_DIR/$TERRAFORM_DIR/_local"
TFVARS_FILE="$STACKS_DIR/$TERRAFORM_DIR/data-stack.tfvars"

# --- Deployment ID Update ---
# Generate random deployment_id if the default placeholder is found.
# This ID is used to identify and delete AWS resources orphaned by Kubernetes Operators.
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

# --- _local Directory Preparation ---
# Clean up _local directory before copying files, preserving state.
if [ -d "$LOCAL_DIR" ]; then
    print_status "Cleaning up $LOCAL_DIR directory..."
    find "$LOCAL_DIR" -mindepth 1 -maxdepth 1 -not -name '.terraform' -not -name '.terraform.lock.hcl' -not -name 'terraform.tfstate*' -exec rm -rf {} +
fi

# Copy base infrastructure files from infra/terraform
print_status "Copying base infrastructure from $REPO_PATH/infra/terraform..."
mkdir -p "$LOCAL_DIR"
cp -r "$REPO_PATH/infra/terraform/"* "$LOCAL_DIR/"

# Apply blueprint files, overwriting any matching base files.
print_status "Overlaying blueprint files from $STACKS_DIR/$TERRAFORM_DIR..."
tar -C "$STACKS_DIR/$TERRAFORM_DIR" --exclude='_local' --exclude='*.tfstate*' --exclude='.terraform' -cf - . | tar -C "$LOCAL_DIR" -xvf -

# --- Terraform Execution ---
print_status "Changing directory to $LOCAL_DIR"
cd "$LOCAL_DIR"

# List of Terraform modules to apply in sequence
targets=(
  "module.vpc"
  "module.eks"
)

# Initialize Terraform
print_status "Initializing Terraform..."
terraform init -upgrade

TERRAFORM_COMMAND="terraform apply -auto-approve"
# Check if data-stack.tfvars exists (relative to _local)
if [ -f "../data-stack.tfvars" ]; then
  TERRAFORM_COMMAND="$TERRAFORM_COMMAND -var-file=../data-stack.tfvars"
fi

# Apply modules in sequence
for target in "${targets[@]}"
do
  print_status "Applying module $target..."
  apply_output=$( $TERRAFORM_COMMAND -target="$target" 2>&1 | tee /dev/tty)
  if [[ ${PIPESTATUS[0]} -eq 0 && $apply_output == *"Apply complete"* ]]; then
    echo "SUCCESS: Terraform apply of $target completed successfully"
  else
    echo "FAILED: Terraform apply of $target failed"
    exit 1
  fi
done

# Final apply to catch any remaining resources
print_status "Applying remaining resources..."
apply_output=$( $TERRAFORM_COMMAND 2>&1 | tee /dev/tty)
if [[ ${PIPESTATUS[0]} -eq 0 && $apply_output == *"Apply complete"* ]]; then
  echo "SUCCESS: Terraform apply of all modules completed successfully"
else
  echo "FAILED: Terraform apply of all modules failed"
  exit 1
fi

print_status "Deployment engine finished successfully."

# --- Return to original directory ---
print_status "Returning to $ORIGINAL_DIR"
cd "$ORIGINAL_DIR"