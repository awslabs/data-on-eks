#!/bin/bash
set -o errexit
set -o pipefail

targets=(
  "module.eks_blueprints_addons"
  "module.eks"
  "module.vpc"
)

for target in "${targets[@]}"
do
  destroy_output=$(terraform destroy -target="$target" -auto-approve)
  if [[ $? -eq 0 && $destroy_output == *"Destroy complete!"* ]]; then
    echo "SUCCESS: Terraform destroy of $target completed successfully"
  else
    echo "FAILED: Terraform destroy of $target failed"
    exit 1
  fi
done

destroy_output=$(terraform destroy -auto-approve)
if [[ $? -eq 0 && $destroy_output == *"Destroy complete!"* ]]; then
  echo "SUCCESS: Terraform destroy of all targets completed successfully"
else
  echo "FAILED: Terraform destroy of all targets failed"
  exit 1
fi
