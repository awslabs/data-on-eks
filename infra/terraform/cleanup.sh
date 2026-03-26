#!/bin/bash

TERRAFORM_COMMAND="terraform destroy -auto-approve"
# Check if data-stack.tfvars exists and add it to the command if it does
if [ -f "../data-stack.tfvars" ]; then
  TERRAFORM_COMMAND="$TERRAFORM_COMMAND -var-file=../data-stack.tfvars"
fi

# Get cluster info from terraform output
CLUSTERNAME=$(terraform output -raw cluster_name)
REGION=$(terraform output -raw region 2>/dev/null || true)

# Check if region contains error/warning messages or is empty
if [[ -z "$REGION" || "$REGION" == *"Warning"* || "$REGION" == *"Error"* || "$REGION" == *"No outputs"* ]]; then
  REGION=""
fi

# Fallback: get region from tfvars if terraform output fails
if [ -z "$REGION" ] && [ -f "../data-stack.tfvars" ]; then
  REGION=$(grep -E '^\s*region\s*=' ../data-stack.tfvars | sed 's/.*=\s*"\(.*\)".*/\1/')
fi

# Final fallback: use AWS CLI default region
if [ -z "$REGION" ]; then
  REGION=$(aws configure get region 2>/dev/null || true)
fi

if [ -z "$REGION" ]; then
  echo "ERROR: Could not determine AWS region"
  exit 1
fi

echo "Destroying Terraform ${CLUSTERNAME:-unknown} in region $REGION"

# Get the deployment_id from terraform output
DEPLOYMENT_ID=$(terraform output -raw deployment_id 2>/dev/null || true)

# Check if deployment_id contains error/warning messages or is empty
if [[ -z "$DEPLOYMENT_ID" || "$DEPLOYMENT_ID" == *"Warning"* || "$DEPLOYMENT_ID" == *"Error"* || "$DEPLOYMENT_ID" == *"No outputs"* ]]; then
  DEPLOYMENT_ID=""
fi

# Fallback: get deployment_id from tfvars if terraform output fails
if [ -z "$DEPLOYMENT_ID" ] && [ -f "../data-stack.tfvars" ]; then
  DEPLOYMENT_ID=$(grep -E '^\s*deployment_id\s*=' ../data-stack.tfvars | sed 's/.*=\s*"\(.*\)".*/\1/')
fi


echo "Destroying RayService..."

# Delete the Ingress/SVC before removing the addons
TMPFILE=$(mktemp)
terraform output -raw configure_kubectl > "$TMPFILE"
# check if TMPFILE contains the string "No outputs found"
if [[ ! $(cat $TMPFILE) == *"No outputs found"* ]]; then
  echo "No outputs found, skipping kubectl delete"
  source "$TMPFILE"
  kubectl delete rayjob -A --all
  kubectl delete rayservice -A --all
fi


# List of Terraform modules to destroy in sequence
targets=($(terraform state list | grep "kubectl_manifest\." | grep -v "kubectl_manifest.aws_load_balancer_controller"))

# Destroy all kubectl_manifest resources at once (excluding aws_load_balancer_controller)
if [ ${#targets[@]} -gt 0 ]; then
  echo "Destroying kubectl_manifest resources..."
  target_args=""
  for target in "${targets[@]}"; do
    target_args="$target_args -target=$target"
  done

  destroy_output=$($TERRAFORM_COMMAND $target_args 2>&1 | tee /dev/tty)
  if [[ ${PIPESTATUS[0]} -eq 0 && $destroy_output == *"Destroy complete"* ]]; then
    echo "SUCCESS: Terraform destroy of kubectl_manifest resources completed successfully"
  else
    echo "FAILED: Terraform destroy of kubectl_manifest resources failed"
    exit 1
  fi
fi


## Final destroy to catch any remaining resources
echo "Destroying remaining resources..."
destroy_output=$($TERRAFORM_COMMAND -var="region=$REGION" 2>&1 | tee /dev/tty)
if [[ ${PIPESTATUS[0]} -eq 0 && $destroy_output == *"Destroy complete"* ]]; then
  echo "SUCCESS: Terraform destroy of all modules completed successfully"
else
  echo "FAILED: Terraform destroy of all modules failed"
  exit 1
fi

echo "Cleaning up PVCs and EBS volumes for deployment_id: $DEPLOYMENT_ID"

# Get the list of EBS volumes with the deployment_id tag
VOLUME_IDS=$(aws ec2 describe-volumes --region "$REGION" --filters "Name=tag:DeploymentId,Values=$DEPLOYMENT_ID" --query "Volumes[].VolumeId" --output text)

if [ -n "$VOLUME_IDS" ]; then
  for volume_id in $VOLUME_IDS; do
    # Get the PVC name from the volume tags
    PVC_NAME=$(aws ec2 describe-volumes --region "$REGION" --volume-ids "$volume_id" --query "Volumes[0].Tags[?Key=='kubernetes.io/created-for/pvc/name'].Value" --output text)
    PVC_NAMESPACE=$(aws ec2 describe-volumes --region "$REGION" --volume-ids "$volume_id" --query "Volumes[0].Tags[?Key=='kubernetes.io/created-for/pvc/namespace'].Value" --output text)

    echo "Deleting EBS volume: $volume_id, PVC: ${PVC_NAME}, Namespace: ${PVC_NAMESPACE}"
    aws ec2 delete-volume --region "$REGION" --volume-id "$volume_id"
  done
else
  echo "No EBS volumes found with deployment_id: $DEPLOYMENT_ID"
fi
