#!/bin/bash
set -o errexit
set -o pipefail

targets=(
  "module.vpc"
  "module.karpenter_policy"
  "module.memory_db"
  "module.eks"
  "module.eks_blueprints_addons"
  "module.eks"
)

for target in "${targets[@]}"
do
  apply_output=$(terraform apply -target="$target" -auto-approve)
  if [[ $? -eq 0 && $apply_output == *"Apply complete!"* ]]; then
    echo "SUCCESS: Terraform apply of $target completed successfully"
  else
    echo "FAILED: Terraform apply of $target failed"
    exit 1
  fi
done

apply_output=$(terraform apply -auto-approve)
if [[ $? -eq 0 && $apply_output == *"Apply complete!"* ]]; then
  echo "SUCCESS: Terraform apply of all targets completed successfully"
else
  echo "FAILED: Terraform apply of all targets failed"
  exit 1
fi
