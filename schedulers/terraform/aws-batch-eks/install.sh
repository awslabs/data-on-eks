#!/bin/bash

read -p "Enter the region: " region
export AWS_DEFAULT_REGION=$region

echo "Initializing ..."
terraform init || echo "\"terraform init\" failed"

# Final apply to catch any remaining resources
echo "Applying resources..."
apply_output=$(terraform apply -var="aws_region=$region" -auto-approve 2>&1 | tee /dev/tty)
if [[ ${PIPESTATUS[0]} -eq 0 && $apply_output == *"Apply complete"* ]]; then
  echo "SUCCESS: Terraform apply of all modules completed successfully"
else
  echo "FAILED: Terraform apply of all modules failed"
  exit 1
fi
