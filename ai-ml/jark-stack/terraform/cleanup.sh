#!/bin/bash

read -p "Enter the region: " region
export AWS_DEFAULT_REGION=$region

echo "Destroying RayService..."

kubectl delete -f src/service/ray-service.yaml

echo "Destroying Load Balancers..."

for arn in $(aws resourcegroupstaggingapi get-resources \
  --resource-type-filters elasticloadbalancing:loadbalancer \
  --tag-filters "Key=elbv2.k8s.aws/cluster,Values=jark-stack" \
  --query 'ResourceTagMappingList[].ResourceARN' \
  --output text); do \
    aws elbv2 delete-load-balancer --load-balancer-arn "$arn"; \
  done

echo "Destroying Target Groups..."
for arn in $(aws resourcegroupstaggingapi get-resources \
  --resource-type-filters elasticloadbalancing:targetgroup \
  --tag-filters "Key=elbv2.k8s.aws/cluster,Values=jark-stack" \
  --query 'ResourceTagMappingList[].ResourceARN' \
  --output text); do \
    aws elbv2 delete-target-group --target-group-arn "$arn"; \
  done

# List of Terraform modules to apply in sequence
targets=(
  "module.data_addons"
  "module.eks_blueprints_addons"
  "module.eks"
  "module.vpc"
)

# Destroy modules in sequence
for target in "${targets[@]}"
do
  echo "Destroying module $target..."
  destroy_output=$(terraform destroy -target="$target" -auto-approve 2>&1 | tee /dev/tty)
  if [[ ${PIPESTATUS[0]} -eq 0 && $destroy_output == *"Destroy complete"* ]]; then
    echo "SUCCESS: Terraform destroy of $target completed successfully"
  else
    echo "FAILED: Terraform destroy of $target failed"
    exit 1
  fi
done

## Final destroy to catch any remaining resources
echo "Destroying remaining resources..."
destroy_output=$(terraform destroy -auto-approve 2>&1 | tee /dev/tty)
if [[ ${PIPESTATUS[0]} -eq 0 && $destroy_output == *"Destroy complete"* ]]; then
  echo "SUCCESS: Terraform destroy of all modules completed successfully"
else
  echo "FAILED: Terraform destroy of all modules failed"
  exit 1
fi
