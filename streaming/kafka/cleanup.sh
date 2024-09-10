#!/bin/bash

read -p "Enter the region: " region
export AWS_DEFAULT_REGION=$region

# List of Terraform modules to apply in sequence
targets=(
  "module.eks_data_addons"
  "module.eks_blueprints_addons"
  "module.eks"
  "module.vpc"
)

# Delete Karpenter resources
kubectl delete --all nodeclaim
kubectl delete --all nodepool
kubectl delete --all ec2nodeclass

# Destroy modules in sequence
for target in "${targets[@]}"
do
  echo "Destroying module $target..."
  destroy_output=$(terraform destroy -target="$target" -var="region=$region" -auto-approve 2>&1 | tee /dev/tty)
  if [[ ${PIPESTATUS[0]} -eq 0 && $destroy_output == *"Destroy complete"* ]]; then
    echo "SUCCESS: Terraform destroy of $target completed successfully"
  else
    echo "FAILED: Terraform destroy of $target failed"
    exit 1
  fi
done

## Final destroy to catch any remaining resources
echo "Destroying remaining resources..."
destroy_output=$(terraform destroy -var="region=$region" -auto-approve 2>&1 | tee /dev/tty)
if [[ ${PIPESTATUS[0]} -eq 0 && $destroy_output == *"Destroy complete"* ]]; then
  echo "SUCCESS: Terraform destroy of all modules completed successfully"
else
  echo "FAILED: Terraform destroy of all modules failed"
  exit 1
fi
