#!/bin/bash

read -p "Enter the region: " region
export AWS_DEFAULT_REGION=$region

echo "Destroying RayService..."

# Delete the Ingress/SVC before removing the addons
TMPFILE=$(mktemp)
terraform output -raw configure_kubectl > "$TMPFILE"
# check if TMPFILE contains the string "No outputs found"
if [[ ! $(cat $TMPFILE) == *"No outputs found"* ]]; then
  echo "No outputs found, skipping kubectl delete"
  source "$TMPFILE"
  kubectl delete -f src/service/ray-service.yaml
fi


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
  destroy_output=$(terraform destroy -target="$target" -var="region=$region" -auto-approve 2>&1 | tee /dev/tty)
  if [[ ${PIPESTATUS[0]} -eq 0 && $destroy_output == *"Destroy complete"* ]]; then
    echo "SUCCESS: Terraform destroy of $target completed successfully"
  else
    echo "FAILED: Terraform destroy of $target failed"
    exit 1
  fi
done

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

echo "Destroying Security Groups..."
for sg in $(aws ec2 describe-security-groups \
  --filters "Name=tag:elbv2.k8s.aws/cluster,Values=jark-stack" \
  --query 'SecurityGroups[].GroupId' --output text); do \
    aws ec2 delete-security-group --group-id "$sg"; \
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
