#!/bin/bash

TERRAFORM_COMMAND="terraform destroy -auto-approve"
CLUSTERNAME="data-on-eks"
REGION="region"
# Check if blueprint.tfvars exists
if [ -f "../blueprint.tfvars" ]; then
  TERRAFORM_COMMAND="$TERRAFORM_COMMAND -var-file=../blueprint.tfvars"
  CLUSTERNAME="$(echo "var.name" | terraform console -var-file=../blueprint.tfvars | tr -d '"')"
  REGION="$(echo "var.region" | terraform console -var-file=../blueprint.tfvars | tr -d '"')"
fi
echo "Destroying Terraform $CLUSTERNAME"
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