#!/bin/bash
set -o errexit
set -o pipefail

read -p "Enter the region: " region
export AWS_DEFAULT_REGION=$region
export AWS_REGION=$AWS_DEFAULT_REGION

echo "Deleting EC2 instances created ..."
# Get the list of instance IDs
instance_ids=$(aws ec2 describe-instances \
  --filters "Name=tag:karpenter.sh/nodepool,Values=kafka" "Name=instance-state-name,Values=running" \
  --query "Reservations[*].Instances[*].InstanceId" \
  --output text)
  
# Terminate the instances
for instance_id in $instance_ids; do
  aws ec2 terminate-instances --instance-ids $instance_id
done

# Wait for the instances to be terminated
for instance_id in $instance_ids; do
  status=$(aws ec2 describe-instances --instance-ids $instance_id --query "Reservations[*].Instances[*].State.Name" --output text)
  while [ "$status" != "terminated" ]; do
    echo "Waiting for instance $instance_id to be terminated..."
    sleep 5
    status=$(aws ec2 describe-instances --instance-ids $instance_id --query "Reservations[*].Instances[*].State.Name" --output text)
  done
done

targets=(
  "module.eks_data_addons"
  "module.eks_blueprints_addons"
  "module.eks"
)

terraform init
  
for target in "${targets[@]}"
do
  terraform destroy -target="$target" -auto-approve
  destroy_output=$(terraform destroy -target="$target" -auto-approve 2>&1)
  if [[ $? -eq 0 && $destroy_output == *"Destroy complete!"* ]]; then
    echo "SUCCESS: Terraform destroy of $target completed successfully"
  else
    echo "FAILED: Terraform destroy of $target failed"
    exit 1
  fi
done

echo "Deleting any remaining EC2 resources ..."

aws ec2 describe-security-groups \
  --filters "Name=tag:kubernetes.io/cluster/kafka-on-eks,Values=owned" \
  --query "SecurityGroups[*].GroupId" \
  --output text | \
xargs -n 1 aws ec2 delete-security-group --group-id

echo "Deleting any remaining resources ..."
terraform destroy -auto-approve
destroy_output=$(terraform destroy -auto-approve 2>&1)
if [[ $? -eq 0 && $destroy_output == *"Destroy complete!"* ]]; then
  echo "SUCCESS: Terraform destroy of all targets completed successfully"
else
  echo "FAILED: Terraform destroy of all targets failed"
  exit 1
fi
