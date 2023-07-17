#!/bin/bash

echo "Initializing ..."
terraform init || echo "\"terraform init\" failed"


echo "Applying ..."
apply_output=$(terraform apply -auto-approve 2>&1 | tee /dev/tty)
if [[ ${PIPESTATUS[0]} -eq 0 && $apply_output == *"Apply complete"* ]]; then
  echo "SUCCESS: Terraform apply completed successfully"
else
  echo "FAILED: Terraform apply failed"
  exit 1
fi
