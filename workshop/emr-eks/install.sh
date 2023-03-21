#!/bin/bash

read -p "Enter the region: " region
export AWS_DEFAULT_REGION=$region

# List of Terraform modules to apply in sequence
targets=(
  "module.vpc_workshop"
  "module.eks_workshop"
  "module.addons_workshop"
  "module.karpenter_provisioners"
  "module.emr_containers_workshop"
)

# Apply modules in sequence
for target in "${targets[@]}"
do
  echo "Applying module $target..."
  terraform apply -target="$target" -auto-approve
  apply_output=$(terraform apply -target="$target" -auto-approve 2>&1)
  if [[ $? -eq 0 && $apply_output == *"Apply complete"* ]]; then
    echo "SUCCESS: Terraform apply of $target completed successfully"
  else
    echo "FAILED: Terraform apply of $target failed"
    exit 1
  fi
done

# Final apply to catch any remaining resources
echo "Applying remaining resources..."
terraform apply -auto-approve
apply_output=$(terraform apply -auto-approve 2>&1)
if [[ $? -eq 0 && $apply_output == *"Apply complete"* ]]; then
  echo "SUCCESS: Terraform apply of all modules completed successfully"
else
  echo "FAILED: Terraform apply of all modules failed"
  exit 1
fi
