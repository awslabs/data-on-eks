#!/bin/bash
set -o errexit
set -o pipefail

read -p "Enter the region: " region
export AWS_DEFAULT_REGION=$region

targets=(
  "module.eks_blueprints_kubernetes_addons"
  "module.eks_blueprints"
)

for target in "${targets[@]}"
do
  destroy_output=$(terraform destroy -target="$target" -auto-approve 2>&1)
  if [[ $? -eq 0 && $destroy_output == *"Destroy complete!"* ]]; then
    echo "SUCCESS: Terraform destroy of $target completed successfully"
  else
    echo "FAILED: Terraform destroy of $target failed"
    exit 1
  fi
done

destroy_output=$(terraform destroy -auto-approve 2>&1)
if [[ $? -eq 0 && $destroy_output == *"Destroy complete!"* ]]; then
  echo "SUCCESS: Terraform destroy of all targets completed successfully"
else
  echo "FAILED: Terraform destroy of all targets failed"
  exit 1
fi
