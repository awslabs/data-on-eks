#!/bin/bash

read -p "Enter the region: " region
export AWS_DEFAULT_REGION=$region

echo "Initializing ..."
terraform init || echo "\"terraform init\" failed"

# List of Terraform modules to apply in sequence
targets=(
  "module.vpc"
  "module.vpc_endpoints_sg"
  "module.vpc_endpoints"
  "module.eks"
  "module.ebs_csi_driver_irsa"
  "module.vpc_cni_irsa"
  "module.eks_blueprints_kubernetes_addons"
  "module.eks_blueprints_addons"
  "module.datahub.module.prereq"
  "module.datahub"
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
