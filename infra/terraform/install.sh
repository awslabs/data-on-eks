#!/bin/bash

# List of Terraform modules to apply in sequence
targets=(
  "module.vpc"
  "module.eks"
)

# Initialize Terraform
terraform init -upgrade

TERRAFORM_COMMAND="terraform apply -auto-approve"
# Check if blueprint.tfvars exists
if [ -f "../blueprint.tfvars" ]; then
  TERRAFORM_COMMAND="$TERRAFORM_COMMAND -var-file=../blueprint.tfvars"
fi

# Apply modules in sequence
for target in "${targets[@]}"
do
  echo "Applying module $target..."
  apply_output=$( $TERRAFORM_COMMAND -target="$target" 2>&1 | tee /dev/tty)
  if [[ ${PIPESTATUS[0]} -eq 0 && $apply_output == *"Apply complete"* ]]; then
    echo "SUCCESS: Terraform apply of $target completed successfully"
  else
    echo "FAILED: Terraform apply of $target failed"
    exit 1
  fi
done

# Final apply to catch any remaining resources
echo "Applying remaining resources..."
apply_output=$( $TERRAFORM_COMMAND 2>&1 | tee /dev/tty)
if [[ ${PIPESTATUS[0]} -eq 0 && $apply_output == *"Apply complete"* ]]; then
  echo "SUCCESS: Terraform apply of all modules completed successfully"
else
  echo "FAILED: Terraform apply of all modules failed"
  exit 1
fi
