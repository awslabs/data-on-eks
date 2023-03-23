#!/bin/bash

read -p "Enter the region: " region
export AWS_DEFAULT_REGION=$region

read -p "Enter Route53 Public Hosted Zone domain (example.com): " domain
export TF_VAR_eks_cluster_domain=$domain

read -p "Enter ACM Certificate domain (*.example.com): " cert_domain
export TF_VAR_acm_certificate_domain=$cert_domain

read -p "Enter the subdomain for NiFi (nifi): " sub_domain
export TF_VAR_nifi_sub_domain=$sub_domain

read -p "Enter NiFi username for login (admin): " username
export TF_VAR_nifi_username=$username

# List of Terraform modules to apply in sequence
targets=(
  "module.vpc"
  "module.eks"
  "module.eks_blueprints_kubernetes_addons"
)

# Apply modules in sequence
for target in "${targets[@]}"
do
  echo "Applying module $target..."
  terraform apply -target="$target" -auto-approve
  apply_output=$(terraform apply -target="$target" -auto-approve 2>&1)
  if [[ $? -eq 0 && $apply_output == *"Apply complete"* ]]; then
    echo "SUCCESS: Terraform apply of $target completed successfully"
  else
    echo "FAILED: Terraform apply of $target failed"
    exit 1
  fi
done

# Final apply to catch any remaining resources
echo "Applying remaining resources..."
terraform apply -auto-approve
apply_output=$(terraform apply -auto-approve 2>&1)
if [[ $? -eq 0 && $apply_output == *"Apply complete"* ]]; then
  echo "SUCCESS: Terraform apply of all modules completed successfully"
else
  echo "FAILED: Terraform apply of all modules failed"
  exit 1
fi