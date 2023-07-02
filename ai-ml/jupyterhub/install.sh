#!/bin/bash
read -p "An ACM Certificate in the account + region where you are deploying.: " acm_certificate_domain

echo "Initializing ..."
terraform init || echo "\"terraform init\" failed"

# List of Terraform modules to apply in sequence
targets=(
  "module.vpc"
  "module.eks"
  "module.vpc_cni_irsa"
  "module.ebs_csi_driver_irsa"
  "module.eks_blueprints_kubernetes_addons"
)

# Apply modules in sequence
for target in "${targets[@]}"
do
  echo "Applying module $target..."
  apply_output=$(terraform apply -target="$target" -var="acm_certificate_domain=$acm_certificate_domain" -auto-approve 2>&1 | tee /dev/tty)
  if [[ ${PIPESTATUS[0]} -eq 0 && $apply_output == *"Apply complete"* ]]; then
    echo "SUCCESS: Terraform apply of $target completed successfully"
  else
    echo "FAILED: Terraform apply of $target failed"
    exit 1
  fi
done

# Final apply to catch any remaining resources
echo "Applying remaining resources..."
apply_output=$(terraform apply -var="acm_certificate_domain=$acm_certificate_domain" -auto-approve 2>&1 | tee /dev/tty)
if [[ ${PIPESTATUS[0]} -eq 0 && $apply_output == *"Apply complete"* ]]; then
  echo "SUCCESS: Terraform apply of all modules completed successfully"
else
  echo "FAILED: Terraform apply of all modules failed"
  exit 1
fi
