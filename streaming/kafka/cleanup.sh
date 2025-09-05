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

# Method 5: Find instances with "karpenter-kafka" specifically
karpenter_kafka_instances=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=*karpenter-kafka*" "Name=instance-state-name,Values=running,pending,stopping,stopped" \
  --query "Reservations[*].Instances[*].InstanceId" \
  --output text 2>/dev/null || echo "")

# Method 6: Find by karpenter.sh/provisioner-name tag (older Karpenter versions)
karpenter_provisioner_instances=$(aws ec2 describe-instances \
  --filters "Name=tag-key,Values=karpenter.sh/provisioner-name" "Name=instance-state-name,Values=running,pending,stopping,stopped" \
  --query "Reservations[*].Instances[*].InstanceId" \
  --output text 2>/dev/null || echo "")

# Method 7: Find by NodeGroupType=kafka tag
nodegroup_kafka_instances=$(aws ec2 describe-instances \
  --filters "Name=tag:NodeGroupType,Values=kafka" "Name=instance-state-name,Values=running,pending,stopping,stopped" \
  --query "Reservations[*].Instances[*].InstanceId" \
  --output text 2>/dev/null || echo "")

# Method 8: Find by launch template name containing "karpenter" or "kafka"
echo "Searching for instances by launch template names..."
launch_template_instances=$(aws ec2 describe-instances \
  --filters "Name=instance-state-name,Values=running,pending,stopping,stopped" \
  --query "Reservations[*].Instances[?LaunchTemplate && (contains(LaunchTemplate.Name, 'karpenter') || contains(LaunchTemplate.Name, 'kafka'))].InstanceId" \
  --output text 2>/dev/null || echo "")

# Combine all instance IDs and remove duplicates
all_instances="$karpenter_instances_1 $karpenter_instances_2 $karpenter_instances_3 $kafka_instances $karpenter_kafka_instances $karpenter_provisioner_instances $nodegroup_kafka_instances $launch_template_instances"
unique_instances=$(echo $all_instances | tr ' ' '\n' | sort -u | tr '\n' ' ')

if [ -n "$unique_instances" ] && [ "$unique_instances" != " " ]; then
  echo "Found instances to terminate:"
  echo "Instance IDs: $unique_instances"
  
  # Show instance details for verification
  echo "Instance details:"
  for instance_id in $unique_instances; do
    if [ -n "$instance_id" ]; then
      instance_info=$(aws ec2 describe-instances --instance-ids $instance_id \
        --query "Reservations[*].Instances[*].[InstanceId,Tags[?Key=='Name'].Value|[0],State.Name,InstanceType]" \
        --output text 2>/dev/null || echo "$instance_id unknown unknown unknown")
      echo "  $instance_info"
    fi
  done
  echo ""
  
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

# First, clean up ENIs that might be holding up VPC deletion
echo "Cleaning up network interfaces..."
enis=$(aws ec2 describe-network-interfaces \
  --query "NetworkInterfaces[?TagSet[?starts_with(Key, 'kubernetes.io/cluster/kafka-on-eks')]].NetworkInterfaceId" \
  --output text 2>/dev/null || echo "")

if [ -n "$enis" ]; then
  for eni in $enis; do
    echo "Detaching and deleting ENI: $eni"
    # First try to detach if attached
    aws ec2 detach-network-interface --network-interface-id $eni --force 2>/dev/null || echo "ENI $eni not attached or failed to detach"
    sleep 5
    # Then delete
    aws ec2 delete-network-interface --network-interface-id $eni 2>/dev/null || echo "Failed to delete ENI $eni"
  done
  echo "Waiting 30 seconds for ENI cleanup..."
  sleep 30
else
  echo "No ENIs found to delete"
fi

# Clean up NAT Gateways
echo "Cleaning up NAT Gateways..."
nat_gateways=$(aws ec2 describe-nat-gateways \
  --query "NatGateways[?Tags[?starts_with(Key, 'kubernetes.io/cluster/kafka-on-eks')] && State=='available'].NatGatewayId" \
  --output text 2>/dev/null || echo "")

if [ -n "$nat_gateways" ]; then
  for nat in $nat_gateways; do
    echo "Deleting NAT Gateway: $nat"
    aws ec2 delete-nat-gateway --nat-gateway-id $nat 2>/dev/null || echo "Failed to delete NAT Gateway $nat"
  done
  echo "Waiting 60 seconds for NAT Gateway deletion..."
  sleep 60
else
  echo "No NAT Gateways found to delete"
fi

# Clean up VPC Endpoints
echo "Cleaning up VPC Endpoints..."
vpc_endpoints=$(aws ec2 describe-vpc-endpoints \
  --query "VpcEndpoints[?Tags[?starts_with(Key, 'kubernetes.io/cluster/kafka-on-eks')]].VpcEndpointId" \
  --output text 2>/dev/null || echo "")

if [ -n "$vpc_endpoints" ]; then
  for endpoint in $vpc_endpoints; do
    echo "Deleting VPC Endpoint: $endpoint"
    aws ec2 delete-vpc-endpoint --vpc-endpoint-id $endpoint 2>/dev/null || echo "Failed to delete VPC Endpoint $endpoint"
  done
  echo "Waiting 30 seconds for VPC Endpoint deletion..."
  sleep 30
else
  echo "No VPC Endpoints found to delete"
fi

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

echo "Cleaning up IAM roles and policies..."

# Try to get the cluster name/hash from Terraform state first
cluster_name=""
if [ -f ".terraform/terraform.tfstate" ] || [ -f "terraform.tfstate" ]; then
  cluster_name=$(terraform output -raw cluster_name 2>/dev/null || echo "")
fi

# If we can't get it from Terraform, try to find it from EKS clusters
if [ -z "$cluster_name" ]; then
  cluster_name=$(aws eks list-clusters --region $region --query "clusters[?starts_with(@, 'kafka-on-eks')]" --output text 2>/dev/null | head -1)
fi

# Extract the hash part (everything after kafka-on-eks-)
if [ -n "$cluster_name" ]; then
  cluster_hash=$(echo $cluster_name | sed 's/kafka-on-eks-//')
  echo "Found cluster: $cluster_name (hash: $cluster_hash)"
else
  echo "WARNING: Could not determine cluster name/hash. Skipping IAM cleanup to avoid deleting unrelated resources."
  echo "If you need to clean up IAM roles manually, look for roles containing: kafka-on-eks-<hash>"
  cluster_hash=""
fi

# Only proceed with IAM cleanup if we have a specific cluster hash
if [ -n "$cluster_hash" ]; then
  echo "Looking for IAM roles with pattern: kafka-on-eks-${cluster_hash}"
  iam_roles=$(aws iam list-roles --query "Roles[?contains(RoleName, 'kafka-on-eks-${cluster_hash}')].RoleName" --output text 2>/dev/null || echo "")
else
  iam_roles=""
fi

if [ -n "$iam_roles" ]; then
  for role in $iam_roles; do
    echo "Cleaning up IAM role: $role"
    
    # First, detach all managed policies
    attached_policies=$(aws iam list-attached-role-policies --role-name $role --query "AttachedPolicies[].PolicyArn" --output text 2>/dev/null || echo "")
    if [ -n "$attached_policies" ]; then
      for policy_arn in $attached_policies; do
        echo "  Detaching policy: $policy_arn"
        aws iam detach-role-policy --role-name $role --policy-arn $policy_arn 2>/dev/null || echo "  Failed to detach policy $policy_arn"
      done
    fi
    
    # Delete inline policies
    inline_policies=$(aws iam list-role-policies --role-name $role --query "PolicyNames" --output text 2>/dev/null || echo "")
    if [ -n "$inline_policies" ]; then
      for policy_name in $inline_policies; do
        echo "  Deleting inline policy: $policy_name"
        aws iam delete-role-policy --role-name $role --policy-name $policy_name 2>/dev/null || echo "  Failed to delete inline policy $policy_name"
      done
    fi
    
    # Remove role from instance profiles
    instance_profiles=$(aws iam list-instance-profiles-for-role --role-name $role --query "InstanceProfiles[].InstanceProfileName" --output text 2>/dev/null || echo "")
    if [ -n "$instance_profiles" ]; then
      for profile in $instance_profiles; do
        echo "  Removing role from instance profile: $profile"
        aws iam remove-role-from-instance-profile --instance-profile-name $profile --role-name $role 2>/dev/null || echo "  Failed to remove role from profile $profile"
        echo "  Deleting instance profile: $profile"
        aws iam delete-instance-profile --instance-profile-name $profile 2>/dev/null || echo "  Failed to delete instance profile $profile"
      done
    fi
    
    # Finally delete the role
    echo "  Deleting IAM role: $role"
    aws iam delete-role --role-name $role 2>/dev/null || echo "  Failed to delete role $role"
  done
else
  echo "No kafka-on-eks IAM roles found to delete"
fi

# Only clean up custom policies if we have a specific cluster hash
if [ -n "$cluster_hash" ]; then
  echo "Cleaning up custom IAM policies..."
  # Find and delete custom policies created specifically for this cluster
  custom_policies=$(aws iam list-policies --scope Local --query "Policies[?contains(PolicyName, 'kafka-on-eks-${cluster_hash}')].Arn" --output text 2>/dev/null || echo "")
else
  custom_policies=""
fi

if [ -n "$custom_policies" ]; then
  for policy_arn in $custom_policies; do
    echo "Deleting custom IAM policy: $policy_arn"
    
    # Delete all policy versions except the default
    policy_versions=$(aws iam list-policy-versions --policy-arn $policy_arn --query "Versions[?!IsDefaultVersion].VersionId" --output text 2>/dev/null || echo "")
    if [ -n "$policy_versions" ]; then
      for version in $policy_versions; do
        echo "  Deleting policy version: $version"
        aws iam delete-policy-version --policy-arn $policy_arn --version-id $version 2>/dev/null || echo "  Failed to delete policy version $version"
      done
    fi
    
    # Delete the policy
    aws iam delete-policy --policy-arn $policy_arn 2>/dev/null || echo "Failed to delete policy $policy_arn"
  done
else
  if [ -n "$cluster_hash" ]; then
    echo "No custom kafka-on-eks-${cluster_hash} IAM policies found to delete"
  else
    echo "Skipped custom IAM policy cleanup (no cluster hash identified)"
  fi
fi

echo "Cleaning up Secrets Manager secrets..."
# Find and delete secrets created for this cluster
secrets=$(aws secretsmanager list-secrets --query "SecretList[?contains(Name, 'kafka-on-eks')].Name" --output text 2>/dev/null || echo "")

if [ -n "$secrets" ]; then
  for secret in $secrets; do
    echo "Deleting Secrets Manager secret: $secret"
    # Force delete immediately (no recovery window)
    aws secretsmanager delete-secret --secret-id $secret --force-delete-without-recovery 2>/dev/null || echo "Failed to delete secret $secret"
  done
else
  echo "No kafka-on-eks secrets found to delete"
fi

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

echo "Final VPC cleanup - detaching Internet Gateways and cleaning up remaining resources..."

# Find and detach Internet Gateways from kafka-on-eks VPCs
echo "Searching for kafka-on-eks VPCs..."

# Try multiple patterns to find VPCs
vpcs_method1=$(aws ec2 describe-vpcs \
  --query "Vpcs[?Tags[?starts_with(Key, 'kubernetes.io/cluster/kafka-on-eks')]].VpcId" \
  --output text 2>/dev/null || echo "")

vpcs_method2=$(aws ec2 describe-vpcs \
  --query "Vpcs[?Tags[?Key=='Name' && contains(Value, 'kafka-on-eks')]].VpcId" \
  --output text 2>/dev/null || echo "")

vpcs_method3=$(aws ec2 describe-vpcs \
  --query "Vpcs[?Tags[?Key=='Name' && contains(Value, 'kafka')]].VpcId" \
  --output text 2>/dev/null || echo "")

# Combine all methods and remove duplicates
all_vpcs="$vpcs_method1 $vpcs_method2 $vpcs_method3"
vpcs=$(echo $all_vpcs | tr ' ' '\n' | sort -u | tr '\n' ' ')

echo "Found VPCs using different methods:"
echo "  Method 1 (cluster tags): $vpcs_method1"
echo "  Method 2 (name contains kafka-on-eks): $vpcs_method2"  
echo "  Method 3 (name contains kafka): $vpcs_method3"
echo "  Combined unique VPCs: $vpcs"

if [ -n "$vpcs" ] && [ "$vpcs" != " " ]; then
  for vpc in $vpcs; do
    echo "Cleaning up VPC: $vpc"
    
    # Detach and delete Internet Gateways
    igws=$(aws ec2 describe-internet-gateways \
      --query "InternetGateways[?Attachments[?VpcId=='$vpc']].InternetGatewayId" \
      --output text 2>/dev/null || echo "")
    
    if [ -n "$igws" ]; then
      for igw in $igws; do
        echo "Detaching Internet Gateway $igw from VPC $vpc"
        aws ec2 detach-internet-gateway --internet-gateway-id $igw --vpc-id $vpc 2>/dev/null || echo "Failed to detach IGW $igw"
        echo "Deleting Internet Gateway: $igw"
        aws ec2 delete-internet-gateway --internet-gateway-id $igw 2>/dev/null || echo "Failed to delete IGW $igw"
      done
    fi
    
    # Clean up route tables (except main)
    route_tables=$(aws ec2 describe-route-tables \
      --query "RouteTables[?VpcId=='$vpc' && !Associations[?Main==\`true\`]].RouteTableId" \
      --output text 2>/dev/null || echo "")
    
    if [ -n "$route_tables" ]; then
      for rt in $route_tables; do
        echo "Deleting route table: $rt"
        aws ec2 delete-route-table --route-table-id $rt 2>/dev/null || echo "Failed to delete route table $rt"
      done
    fi
    
    # Clean up subnets
    subnets=$(aws ec2 describe-subnets \
      --query "Subnets[?VpcId=='$vpc'].SubnetId" \
      --output text 2>/dev/null || echo "")
    
    if [ -n "$subnets" ]; then
      for subnet in $subnets; do
        echo "Deleting subnet: $subnet"
        aws ec2 delete-subnet --subnet-id $subnet 2>/dev/null || echo "Failed to delete subnet $subnet"
      done
    fi
    
    # Wait a bit for resources to be cleaned up
    echo "Waiting 30 seconds for VPC resource cleanup..."
    sleep 30
    
    # Check for any remaining dependencies before VPC deletion
    echo "Checking for remaining VPC dependencies..."
    
    # Check for remaining ENIs
    remaining_enis=$(aws ec2 describe-network-interfaces \
      --query "NetworkInterfaces[?VpcId=='$vpc'].NetworkInterfaceId" \
      --output text 2>/dev/null || echo "")
    if [ -n "$remaining_enis" ]; then
      echo "WARNING: Found remaining ENIs in VPC $vpc: $remaining_enis"
      for eni in $remaining_enis; do
        echo "Force deleting ENI: $eni"
        aws ec2 detach-network-interface --network-interface-id $eni --force 2>/dev/null
        sleep 5
        aws ec2 delete-network-interface --network-interface-id $eni 2>/dev/null || echo "Failed to delete ENI $eni"
      done
      sleep 15
    fi
    
    # Check for remaining security groups (except default)
    remaining_sgs=$(aws ec2 describe-security-groups \
      --query "SecurityGroups[?VpcId=='$vpc' && GroupName!='default'].GroupId" \
      --output text 2>/dev/null || echo "")
    if [ -n "$remaining_sgs" ]; then
      echo "WARNING: Found remaining security groups in VPC $vpc: $remaining_sgs"
      for sg in $remaining_sgs; do
        echo "Force deleting security group: $sg"
        aws ec2 delete-security-group --group-id $sg 2>/dev/null || echo "Failed to delete SG $sg"
      done
      sleep 10
    fi
    
    # Check for remaining NAT Gateways
    remaining_nats=$(aws ec2 describe-nat-gateways \
      --query "NatGateways[?VpcId=='$vpc' && State!='deleted'].NatGatewayId" \
      --output text 2>/dev/null || echo "")
    if [ -n "$remaining_nats" ]; then
      echo "WARNING: Found remaining NAT Gateways in VPC $vpc: $remaining_nats"
      for nat in $remaining_nats; do
        echo "Force deleting NAT Gateway: $nat"
        aws ec2 delete-nat-gateway --nat-gateway-id $nat 2>/dev/null || echo "Failed to delete NAT $nat"
      done
      echo "Waiting additional 60 seconds for NAT Gateway cleanup..."
      sleep 60
    fi
    
    # Check for VPC peering connections
    peering_connections=$(aws ec2 describe-vpc-peering-connections \
      --query "VpcPeeringConnections[?AccepterVpcInfo.VpcId=='$vpc' || RequesterVpcInfo.VpcId=='$vpc'].VpcPeeringConnectionId" \
      --output text 2>/dev/null || echo "")
    if [ -n "$peering_connections" ]; then
      echo "WARNING: Found VPC peering connections: $peering_connections"
      for pc in $peering_connections; do
        echo "Deleting VPC peering connection: $pc"
        aws ec2 delete-vpc-peering-connection --vpc-peering-connection-id $pc 2>/dev/null || echo "Failed to delete peering connection $pc"
      done
    fi
    
    # Check for VPN connections
    vpn_connections=$(aws ec2 describe-vpn-connections \
      --query "VpnConnections[?VpcId=='$vpc' && State!='deleted'].VpnConnectionId" \
      --output text 2>/dev/null || echo "")
    if [ -n "$vpn_connections" ]; then
      echo "WARNING: Found VPN connections: $vpn_connections"
      for vpn in $vpn_connections; do
        echo "Deleting VPN connection: $vpn"
        aws ec2 delete-vpn-connection --vpn-connection-id $vpn 2>/dev/null || echo "Failed to delete VPN connection $vpn"
      done
    fi
    
    # Final attempt to delete the VPC with detailed error reporting
    echo "Attempting to delete VPC: $vpc"
    vpc_delete_result=$(aws ec2 delete-vpc --vpc-id $vpc 2>&1)
    if [ $? -eq 0 ]; then
      echo "SUCCESS: VPC $vpc deleted"
    else
      echo "FAILED: VPC $vpc deletion failed with error:"
      echo "$vpc_delete_result"
      echo ""
      echo "Remaining resources in VPC $vpc:"
      
      # Show what's still in the VPC
      echo "- ENIs:"
      aws ec2 describe-network-interfaces --query "NetworkInterfaces[?VpcId=='$vpc'].[NetworkInterfaceId,Description,Status]" --output table 2>/dev/null || echo "  None found"
      
      echo "- Security Groups:"
      aws ec2 describe-security-groups --query "SecurityGroups[?VpcId=='$vpc'].[GroupId,GroupName]" --output table 2>/dev/null || echo "  None found"
      
      echo "- Subnets:"
      aws ec2 describe-subnets --query "Subnets[?VpcId=='$vpc'].[SubnetId,AvailabilityZone]" --output table 2>/dev/null || echo "  None found"
      
      echo "- Route Tables:"
      aws ec2 describe-route-tables --query "RouteTables[?VpcId=='$vpc'].[RouteTableId,Associations[0].Main]" --output table 2>/dev/null || echo "  None found"
      
      echo "- Internet Gateways:"
      aws ec2 describe-internet-gateways --query "InternetGateways[?Attachments[?VpcId=='$vpc']].[InternetGatewayId,State]" --output table 2>/dev/null || echo "  None found"
      
      echo "- NAT Gateways:"
      aws ec2 describe-nat-gateways --query "NatGateways[?VpcId=='$vpc'].[NatGatewayId,State]" --output table 2>/dev/null || echo "  None found"
      
      echo ""
      echo "Manual cleanup may be required for VPC $vpc"
    fi
  done
else
  echo "No kafka-on-eks VPCs found with automatic detection"
  echo "Showing all VPCs in region for manual identification:"
  aws ec2 describe-vpcs \
    --query "Vpcs[].[VpcId,Tags[?Key=='Name'].Value|[0],State,CidrBlock]" \
    --output table 2>/dev/null || echo "Failed to list VPCs"
  
  echo ""
  echo "If you see a kafka-related VPC above, you may need to delete it manually:"
  echo "  aws ec2 delete-vpc --vpc-id <vpc-id>"
fi

echo "Final cleanup - destroying any remaining Terraform resources..."
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
