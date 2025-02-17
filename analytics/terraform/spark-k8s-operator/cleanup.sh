#!/bin/bash
set -o errexit
set -o pipefail

read -p "Enter the region: " region
export AWS_DEFAULT_REGION=$region
export STACK_NAME=$(terraform output -raw cluster_name)

targets=(
  "module.eks_data_addons"
  "module.eks_blueprints_addons"
  "module.eks"
)

for target in "${targets[@]}"
do
  echo "Destroying module $target..."
  destroy_output=$(terraform destroy -target="$target" -var="region=$region" -auto-approve 2>&1 | tee /dev/tty)
  if [[ ${PIPESTATUS[0]} -eq 0 && $destroy_output == *"Destroy complete!"* ]]; then
    echo "SUCCESS: Terraform destroy of $target completed successfully"
  else
    echo "FAILED: Terraform destroy of $target failed"
    exit 1
  fi
done

# delete any orphaned ELBs and resources https://github.com/awslabs/data-on-eks/issues/741
echo "Destroying Load Balancers..."
for arn in $(aws resourcegroupstaggingapi get-resources \
  --resource-type-filters elasticloadbalancing:loadbalancer \
  --tag-filters "Key=elbv2.k8s.aws/cluster,Values=${STACK_NAME}" \
  --query 'ResourceTagMappingList[].ResourceARN' \
  --output text \
  --no-cli-pager); do \
    aws elbv2 delete-load-balancer --load-balancer-arn "$arn" --no-cli-pager; \
  done

echo "Destroying Target Groups..."
for arn in $(aws resourcegroupstaggingapi get-resources \
  --resource-type-filters elasticloadbalancing:targetgroup \
  --tag-filters "Key=elbv2.k8s.aws/cluster,Values=${STACK_NAME}" \
  --query 'ResourceTagMappingList[].ResourceARN' \
  --output text \
  --no-cli-pager); do \
    aws elbv2 delete-target-group --target-group-arn "$arn" --no-cli-pager; \
  done

echo "Destroying Security Groups..."
for sg in $(aws ec2 describe-security-groups \
  --filters "Name=tag:elbv2.k8s.aws/cluster,Values=${STACK_NAME}" \
  --query 'SecurityGroups[].GroupId' --output text --no-cli-pager); do \
    aws ec2 delete-security-group --group-id "$sg" --no-cli-pager; \
  done

echo "Destroying remaining resources..."
destroy_output=$(terraform destroy -var="region=$region" -auto-approve 2>&1 | tee /dev/tty)
if [[ ${PIPESTATUS[0]} -eq 0 && $destroy_output == *"Destroy complete!"* ]]; then
  echo "SUCCESS: Terraform destroy of all targets completed successfully"
else
  echo "FAILED: Terraform destroy of all targets failed"
  exit 1
fi
