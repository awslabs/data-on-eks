#!/bin/bash

# Check if AWS_REGION is already set
if [ -z "$AWS_REGION" ]; then
  read -p "Enter the AWS region: " region
  export AWS_REGION=$region
  export AWS_DEFAULT_REGION=$region
  echo "AWS_REGION set to: $AWS_REGION"
else
  region=$AWS_REGION
  export AWS_DEFAULT_REGION=$AWS_REGION
  echo "Using existing AWS_REGION: $AWS_REGION"
fi

# List of Terraform modules to apply in sequence
targets=(
  "module.vpc"
  "module.eks"
  "module.ebs_csi_driver_irsa"
  "module.eks_blueprints_addons"
  "module.eks_data_addons"
)

# Clean up any existing state issues and reinitialize Terraform
echo "Cleaning up Terraform cache and reinitializing..."
rm -rf .terraform.lock.hcl
rm -rf .terraform/modules
rm -rf .terraform/providers
rm -rf .terraform

# Force a clean initialization with provider upgrade
echo "Performing clean Terraform initialization..."
terraform init -upgrade -reconfigure

# Apply modules in sequence
for target in "${targets[@]}"
do
  echo "Applying module $target..."
  apply_output=$(terraform apply -target="$target" -var="region=$region" -auto-approve 2>&1 | tee /dev/tty)
  if [[ ${PIPESTATUS[0]} -eq 0 && $apply_output == *"Apply complete"* ]]; then
    echo "SUCCESS: Terraform apply of $target completed successfully"
  else
    echo "FAILED: Terraform apply of $target failed"
    exit 1
  fi
done

# Final apply to catch any remaining resources
echo "Applying remaining resources..."
apply_output=""
max_retry=3
counter=1
until apply_output=$(terraform apply -var="region=$region" -auto-approve 2>&1 | tee /dev/tty)
do
    [[ counter -eq $max_retry ]] && exit 1
    echo "FAILED: Terraform apply failed, will wait 30 seconds and retry. Try #$counter"
    sleep 30
    ((counter++))
done

if [[ ${PIPESTATUS[0]} -eq 0 && $apply_output == *"Apply complete"* ]]; then
  echo "SUCCESS: Terraform apply of all modules completed successfully"
else
  echo "FAILED: Terraform apply of all modules failed"
  exit 1
fi
