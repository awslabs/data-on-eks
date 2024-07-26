#!/bin/bash
set -o errexit
set -o pipefail

read -p "Enter the region: " region

# Assign the tag key and value to variables
TAG_KEY="aws:eks:cluster-name"
TAG_VALUE="eks-spark-s3-bench"

# Get the instance IDs of running instances matching the tag
INSTANCE_IDS=$(aws ec2 describe-instances --region $region \
                --filters "Name=instance-state-name,Values=running" \
                          "Name=tag:$TAG_KEY,Values=$TAG_VALUE" \
                --query 'Reservations[].Instances[].InstanceId' \
                --output text)

# Check if any instances were found
if [ -z "$INSTANCE_IDS" ]; then
    echo "No running instances found with tag $TAG_KEY=$TAG_VALUE"
else
  for instance_id in $INSTANCE_IDS; do
    aws ec2 terminate-instances --region $region --instance-ids $instance_id
    echo "Terminated instances: $instance_id"
  done
fi

# Get the list of security group IDs with the specified tag
group_ids=$(aws ec2 describe-security-groups --region $region \
                --filters "Name=tag:$TAG_KEY,Values=$TAG_VALUE" \
                --query 'SecurityGroups[*].GroupId' \
                --output text)

echo $group_ids
# Check if any security groups were found
if [ -z "$group_ids" ]; then
    echo "No security groups found with tag $TAG_KEY=$TAG_VALUE"
else
  for group_id in $group_ids; do
        aws ec2 delete-security-group --region $region --group-id "$group_id"
        echo "Deleted security group $group_id"
  done
fi

# Destroy Terraform infrastructure
echo "Destroy Terraform infrastructure..."
terraform destroy -auto-approve
destroy_output=$(terraform destroy -auto-approve 2>&1)
if [[ $? -eq 0 && $destroy_output == *"Destroy complete!"* ]]; then
  echo "SUCCESS: Terraform destroy of all components completed successfully"
else
  echo "FAILED: Terraform destroy of all components"
  exit 1
fi