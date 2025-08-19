#!/bin/bash
# Note: Not using 'set -o errexit' because cleanup should continue even if some commands fail
set -o pipefail

# Check if AWS_REGION is already set
if [ -z "$AWS_REGION" ]; then
  read -p "Enter the AWS region: " region
  export AWS_REGION=$region
  export AWS_DEFAULT_REGION=$region
  echo "AWS_REGION set to: $AWS_REGION"
else
  region=$AWS_REGION
  export AWS_DEFAULT_REGION=$AWS_REGION
  echo "Using existing AWS_REGION: $AWS_REGION"
fi

echo "Deleting ALL EC2 instances created by Karpenter..."

# Find ALL Karpenter instances using multiple tag patterns
echo "Finding Karpenter instances by various tags..."

# Method 1: Find by karpenter.sh/nodepool tag (any value)
karpenter_instances_1=$(aws ec2 describe-instances \
  --filters "Name=tag-key,Values=karpenter.sh/nodepool" "Name=instance-state-name,Values=running,pending,stopping,stopped" \
  --query "Reservations[*].Instances[*].InstanceId" \
  --output text 2>/dev/null || echo "")

# Method 2: Find by instance name containing "karpenter"
karpenter_instances_2=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=*karpenter*" "Name=instance-state-name,Values=running,pending,stopping,stopped" \
  --query "Reservations[*].Instances[*].InstanceId" \
  --output text 2>/dev/null || echo "")

# Method 3: Find by karpenter.sh/cluster tag
karpenter_instances_3=$(aws ec2 describe-instances \
  --filters "Name=tag-key,Values=karpenter.sh/cluster" "Name=instance-state-name,Values=running,pending,stopping,stopped" \
  --query "Reservations[*].Instances[*].InstanceId" \
  --output text 2>/dev/null || echo "")

# Method 4: Find instances with "kafka" in the name
kafka_instances=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=*kafka*" "Name=instance-state-name,Values=running,pending,stopping,stopped" \
  --query "Reservations[*].Instances[*].InstanceId" \
  --output text 2>/dev/null || echo "")

# Combine all instance IDs and remove duplicates
all_instances="$karpenter_instances_1 $karpenter_instances_2 $karpenter_instances_3 $kafka_instances"
unique_instances=$(echo $all_instances | tr ' ' '\n' | sort -u | tr '\n' ' ')

if [ -n "$unique_instances" ] && [ "$unique_instances" != " " ]; then
  echo "Found instances to terminate: $unique_instances"
  
  # Terminate all instances
  for instance_id in $unique_instances; do
    if [ -n "$instance_id" ]; then
      echo "Terminating instance: $instance_id"
      # Get instance name for logging
      instance_name=$(aws ec2 describe-instances --instance-ids $instance_id \
        --query "Reservations[*].Instances[*].Tags[?Key=='Name'].Value" \
        --output text 2>/dev/null || echo "unknown")
      echo "  Instance name: $instance_name"
      
      aws ec2 terminate-instances --instance-ids $instance_id 2>/dev/null || echo "  Failed to terminate $instance_id"
    fi
  done

  # Wait for ALL instances to be terminated
  echo "Waiting for all instances to terminate..."
  for instance_id in $unique_instances; do
    if [ -n "$instance_id" ]; then
      echo "Waiting for instance $instance_id to terminate..."
      while true; do
        status=$(aws ec2 describe-instances --instance-ids $instance_id \
          --query "Reservations[*].Instances[*].State.Name" \
          --output text 2>/dev/null || echo "terminated")
        
        if [ "$status" = "terminated" ] || [ "$status" = "" ]; then
          echo "  Instance $instance_id terminated"
          break
        fi
        
        echo "  Instance $instance_id status: $status"
        sleep 10
      done
    fi
  done
  
  # Additional wait to ensure ENIs are released
  echo "Waiting additional 30 seconds for ENI cleanup..."
  sleep 30
else
  echo "No Karpenter or Kafka instances found to terminate"
fi

echo "Cleaning up KMS aliases that might conflict..."
# Find and delete KMS aliases that match the kafka-on-eks pattern
kms_aliases=$(aws kms list-aliases --query "Aliases[?starts_with(AliasName, 'alias/eks/kafka-on-eks')].AliasName" --output text 2>/dev/null || echo "")

if [ -n "$kms_aliases" ]; then
  for alias in $kms_aliases; do
    echo "Deleting KMS alias: $alias"
    aws kms delete-alias --alias-name $alias 2>/dev/null || echo "Failed to delete alias $alias"
  done
else
  echo "No kafka-on-eks KMS aliases found to delete"
fi

# Clean up Terraform state and reinitialize
echo "Cleaning up Terraform cache and reinitializing..."
rm -rf .terraform.lock.hcl
rm -rf .terraform/modules
terraform init

echo "Attempting to destroy all resources at once..."
# Try to destroy everything at once first - this often works better than targeted destroys
destroy_output=$(terraform destroy -var="region=$region" -auto-approve 2>&1 | tee /dev/tty)
if [[ ${PIPESTATUS[0]} -eq 0 && $destroy_output == *"Destroy complete!"* ]]; then
  echo "SUCCESS: Terraform destroy completed successfully"
else
  echo "Full destroy failed, trying targeted approach..."
  
  # If full destroy fails, try targeted destroys in correct dependency order
  # Note: VPC should be destroyed LAST since everything depends on it
  targets=(
    "module.eks_data_addons"
    "module.eks_blueprints_addons"
    "module.ebs_csi_driver_irsa"
    "module.eks"
  )
  
  for target in "${targets[@]}"
  do
    echo "Destroying module $target..."
    terraform destroy -target="$target" -var="region=$region" -auto-approve 2>/dev/null || echo "WARNING: Failed to destroy $target, continuing..."
  done
  
  # Destroy VPC last since everything depends on it
  echo "Destroying VPC (last step)..."
  terraform destroy -target="module.vpc" -var="region=$region" -auto-approve 2>/dev/null || echo "WARNING: Failed to destroy VPC, continuing..."
fi

echo "Checking for any remaining EKS clusters..."
# Find and delete any remaining kafka-on-eks clusters
remaining_clusters=$(aws eks list-clusters --region $region --query "clusters[?starts_with(@, 'kafka-on-eks')]" --output text 2>/dev/null || echo "")

if [ -n "$remaining_clusters" ]; then
  for cluster in $remaining_clusters; do
    echo "WARNING: Found remaining EKS cluster: $cluster"
    
    # First, delete all node groups
    echo "Deleting node groups for cluster: $cluster"
    node_groups=$(aws eks list-nodegroups --cluster-name $cluster --region $region --query "nodegroups" --output text 2>/dev/null || echo "")
    if [ -n "$node_groups" ]; then
      for ng in $node_groups; do
        echo "Deleting node group: $ng"
        aws eks delete-nodegroup --cluster-name $cluster --nodegroup-name $ng --region $region 2>/dev/null || echo "Failed to delete node group $ng"
      done
      
      # Wait a bit for node groups to start deleting
      echo "Waiting 30 seconds for node groups to start deletion..."
      sleep 30
    fi
    
    # Then delete the cluster
    echo "Attempting to delete cluster: $cluster"
    aws eks delete-cluster --name $cluster --region $region 2>/dev/null || echo "Failed to delete cluster $cluster"
  done
else
  echo "No remaining EKS clusters found"
fi

echo "Deleting any remaining EC2 resources..."

# Delete security groups with error handling - find all kafka-on-eks clusters
security_groups=$(aws ec2 describe-security-groups \
  --query "SecurityGroups[?Tags[?starts_with(Key, 'kubernetes.io/cluster/kafka-on-eks') && Value=='owned']].GroupId" \
  --output text 2>/dev/null || echo "")

if [ -n "$security_groups" ]; then
  for sg in $security_groups; do
    echo "Deleting security group: $sg"
    aws ec2 delete-security-group --group-id $sg 2>/dev/null || echo "Failed to delete security group $sg (may be in use)"
  done
else
  echo "No security groups found to delete"
fi

echo "Cleaning up load balancers that might hold ENIs..."
# Clean up Application Load Balancers
albs=$(aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?Tags[?Key=='kubernetes.io/cluster/*kafka-on-eks*']].LoadBalancerArn" \
  --output text 2>/dev/null || echo "")

if [ -n "$albs" ]; then
  for alb in $albs; do
    echo "Deleting ALB: $alb"
    aws elbv2 delete-load-balancer --load-balancer-arn $alb 2>/dev/null || echo "Failed to delete ALB $alb"
  done
fi

# Clean up Classic Load Balancers
clbs=$(aws elb describe-load-balancers \
  --query "LoadBalancerDescriptions[?Tags[?Key=='kubernetes.io/cluster/*kafka-on-eks*']].LoadBalancerName" \
  --output text 2>/dev/null || echo "")

if [ -n "$clbs" ]; then
  for clb in $clbs; do
    echo "Deleting CLB: $clb"
    aws elb delete-load-balancer --load-balancer-name $clb 2>/dev/null || echo "Failed to delete CLB $clb"
  done
fi

# Wait for load balancers to be deleted
echo "Waiting for load balancers to be deleted..."
sleep 30

echo "Cleaning up any remaining KMS keys..."
# Find and schedule deletion of KMS keys created for this cluster
kms_keys=$(aws kms list-keys --query "Keys[*].KeyId" --output text)
for key_id in $kms_keys; do
  key_description=$(aws kms describe-key --key-id $key_id --query "KeyMetadata.Description" --output text 2>/dev/null || echo "")
  if [[ "$key_description" == *"kafka-on-eks"* ]]; then
    echo "Disabling and scheduling deletion of KMS key: $key_id"
    # Disable the key immediately to prevent usage
    aws kms disable-key --key-id $key_id 2>/dev/null || echo "Failed to disable key $key_id"
    # Schedule deletion with minimum waiting period (7 days)
    aws kms schedule-key-deletion --key-id $key_id --pending-window-in-days 7 2>/dev/null || echo "Failed to schedule deletion of key $key_id"
  fi
done

echo "Final cleanup - destroying any remaining resources..."
terraform destroy -var="region=$region" -auto-approve 2>/dev/null || echo "Final destroy completed with some warnings"

# If there are still resources, try to remove them from state and force cleanup
echo "Checking if any resources remain in Terraform state..."
remaining_resources=$(terraform state list 2>/dev/null || echo "")
if [ -n "$remaining_resources" ]; then
  echo "WARNING: Found remaining resources in Terraform state:"
  echo "$remaining_resources"
  echo "Attempting to remove them from state..."
  
  # Remove each resource from state (this doesn't delete the actual resource, just removes tracking)
  echo "$remaining_resources" | while read resource; do
    if [ -n "$resource" ]; then
      echo "Removing $resource from state..."
      terraform state rm "$resource" 2>/dev/null || echo "Failed to remove $resource from state"
    fi
  done
fi

echo "Cleanup process completed. Some resources may need manual cleanup if errors occurred."
