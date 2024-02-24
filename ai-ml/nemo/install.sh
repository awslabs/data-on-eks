#!/bin/bash

# List of Terraform modules to apply in sequence
targets=(
  "module.vpc"
  "module.eks"
  "module.ebs_csi_driver_irsa"
  "module.eks_blueprints_addons"
)

# Initialize Terraform
echo "Initializing ..."
terraform init --upgrade || echo "\"terraform init\" failed"

# Apply modules in sequence
for target in "${targets[@]}"
do
  echo "Applying module $target..."
  apply_output=$(terraform apply -target="$target" -auto-approve 2>&1 | tee /dev/tty)
  if [[ ${PIPESTATUS[0]} -eq 0 && $apply_output == *"Apply complete"* ]]; then
    echo "SUCCESS: Terraform apply of $target completed successfully"
  else
    echo "FAILED: Terraform apply of $target failed"
    exit 1
  fi
done

# Final apply to catch any remaining resources
echo "Applying remaining resources..."
apply_output=$(terraform apply -auto-approve 2>&1 | tee /dev/tty)
if [[ ${PIPESTATUS[0]} -eq 0 && $apply_output == *"Apply complete"* ]]; then
  echo "SUCCESS: Terraform apply of all modules completed successfully"
else
  echo "FAILED: Terraform apply of all modules failed"
  exit 1
fi

# Install kubeflow training module separately due to version conflicts
if kubectl get deployment training-operator -n kubeflow &> /dev/null; then
  echo "Training operator already exists. Exiting."
  exit 0
else
  git clone https://github.com/kubeflow/training-operator.git -b v1.6-branch /tmp/training-operator
  cp ./training-operator/deployment.yaml /tmp/training-operator/manifests/base/deployment.yaml
  cp ./training-operator/kustomization.yaml /tmp/training-operator/manifests/base/crds/kustomization.yaml
  kubectl apply -k /tmp/training-operator/manifests/overlays/standalone
  echo "Successfully installed customer training-operator."
fi

# Set nvidia ngc api key https://org.ngc.nvidia.com/setup/api-key
if kubectl get secret ngc-registry &> /dev/null; then
  echo "NGC API KEY is already set. Exiting."
  exit 0
else
  echo "Follow https://org.ngc.nvidia.com/setup/api-key"
  echo "Run: " 
  echo "kubectl create secret docker-registry ngc-registry --docker-server=nvcr.io --docker-username=\$oauthtoken --docker-password=<NGC KEY HERE>"
fi
