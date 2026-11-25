#!/bin/bash

# Relative paths must work from any directory.
cd "$(dirname "${BASH_SOURCE[0]}")"
TERRAFORM_DIR="terraform"
TFVARS_FILE="$TERRAFORM_DIR/data-stack.tfvars"
TF="terraform -chdir=$TERRAFORM_DIR"

TERRAFORM_COMMAND="$TF destroy -auto-approve"
# -var-file is relative to TERRAFORM_DIR, because -chdir changes the directory first.
if [ -f "$TFVARS_FILE" ]; then
  TERRAFORM_COMMAND="$TERRAFORM_COMMAND -var-file=data-stack.tfvars"
fi

CLUSTERNAME=$($TF output -raw cluster_name)
REGION=$($TF output -raw region 2>/dev/null || true)

if [[ -z "$REGION" || "$REGION" == *"Warning"* || "$REGION" == *"Error"* || "$REGION" == *"No outputs"* ]]; then
  REGION=""
fi

if [ -z "$REGION" ] && [ -f "$TFVARS_FILE" ]; then
  REGION=$(grep -E '^[[:space:]]*region[[:space:]]*=' "$TFVARS_FILE" | sed -E 's/.*=[[:space:]]*"([^"]*)".*/\1/')
fi

if [ -z "$REGION" ]; then
  REGION=$(aws configure get region 2>/dev/null || true)
fi

if [ -z "$REGION" ]; then
  echo "ERROR: Could not determine AWS region"
  exit 1
fi

echo "Destroying Terraform ${CLUSTERNAME:-unknown} in region $REGION"

DEPLOYMENT_ID=$($TF output -raw deployment_id 2>/dev/null || true)

if [[ -z "$DEPLOYMENT_ID" || "$DEPLOYMENT_ID" == *"Warning"* || "$DEPLOYMENT_ID" == *"Error"* || "$DEPLOYMENT_ID" == *"No outputs"* ]]; then
  DEPLOYMENT_ID=""
fi

if [ -z "$DEPLOYMENT_ID" ] && [ -f "$TFVARS_FILE" ]; then
  DEPLOYMENT_ID=$(grep -E '^[[:space:]]*deployment_id[[:space:]]*=' "$TFVARS_FILE" | sed -E 's/.*=[[:space:]]*"([^"]*)".*/\1/')
fi


echo "Destroying RayService..."

# Delete the Ray resources before Terraform removes the add-ons.
TMPFILE=$(mktemp)
$TF output -raw configure_kubectl > "$TMPFILE"
if [[ ! $(cat $TMPFILE) == *"No outputs found"* ]]; then
  echo "No outputs found, skipping kubectl delete"
  source "$TMPFILE"
  kubectl delete rayjob -A --all
  kubectl delete rayservice -A --all
fi


# Terraform deletes VPC routes at the same time as the EKS cluster.
# Nodes that are still running can then lose network access.
echo "Draining nodes before terraform destroy..."
if [[ ! $(cat $TMPFILE) == *"No outputs found"* ]]; then
  echo "Deleting all nodepools..."
  kubectl delete nodepool --all --wait=true --timeout=300s 2>/dev/null || echo "WARNING: No nodepools found or delete failed"
  echo "Node drain complete"
fi

targets=($($TF state list | grep "kubectl_manifest\." | grep -v "kubectl_manifest.aws_load_balancer_controller"))

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


# Destroy EKS before the VPC. The NAT gateway and VPC endpoints must stay available while nodes drain.
echo "Destroying EKS resources first (preserving VPC for pod cleanup)..."
destroy_output=$($TERRAFORM_COMMAND -var="region=$REGION" -target=module.eks 2>&1 | tee /dev/tty)
if [[ ${PIPESTATUS[0]} -eq 0 && $destroy_output == *"Destroy complete"* ]]; then
  echo "SUCCESS: EKS resources destroyed"
else
  echo "FAILED: EKS destroy failed"
  exit 1
fi

echo "Destroying remaining resources..."
destroy_output=$($TERRAFORM_COMMAND -var="region=$REGION" 2>&1 | tee /dev/tty)
if [[ ${PIPESTATUS[0]} -eq 0 && $destroy_output == *"Destroy complete"* ]]; then
  echo "SUCCESS: Terraform destroy of all modules completed successfully"
else
  echo "FAILED: Terraform destroy of all modules failed"
  exit 1
fi

echo "Cleaning up PVCs and EBS volumes for deployment_id: $DEPLOYMENT_ID"

VOLUME_IDS=$(aws ec2 describe-volumes --region "$REGION" --filters "Name=tag:DeploymentId,Values=$DEPLOYMENT_ID" --query "Volumes[].VolumeId" --output text)

if [ -n "$VOLUME_IDS" ]; then
  for volume_id in $VOLUME_IDS; do
    PVC_NAME=$(aws ec2 describe-volumes --region "$REGION" --volume-ids "$volume_id" --query "Volumes[0].Tags[?Key=='kubernetes.io/created-for/pvc/name'].Value" --output text)
    PVC_NAMESPACE=$(aws ec2 describe-volumes --region "$REGION" --volume-ids "$volume_id" --query "Volumes[0].Tags[?Key=='kubernetes.io/created-for/pvc/namespace'].Value" --output text)

    echo "Deleting EBS volume: $volume_id, PVC: ${PVC_NAME}, Namespace: ${PVC_NAMESPACE}"
    aws ec2 delete-volume --region "$REGION" --volume-id "$volume_id"
  done
else
  echo "No EBS volumes found with deployment_id: $DEPLOYMENT_ID"
fi
