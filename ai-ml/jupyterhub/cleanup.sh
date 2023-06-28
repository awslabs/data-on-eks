#!/bin/bash
set -o errexit
set -o pipefail

read -p "Enter acm certificate: " acm_certificate_domain

targets=(
  "module.kubernetes_data_addons"
  "module.eks_blueprints_kubernetes_addons"
  "module.ebs_csi_driver_irsa"
  "module.vpc_cni_irsa"
  "aws_cognito_user_pool.pool"
  "aws_cognito_user_pool_domain.domain"
  "aws_cognito_user_pool_client.user_pool_client"
  "module.eks"
  "module.vpc"
)


#-------------------------------------------
# Terraform destroy per module target
#-------------------------------------------
for target in "${targets[@]}"
do
  terraform destroy -target="$target" -var="acm_certificate_domain=$acm_certificate_domain" -auto-approve
  destroy_output=$(terraform destroy -target="$target" -var="acm_certificate_domain=$acm_certificate_domain" -auto-approve 2>&1)
  if [[ $? -eq 0 && $destroy_output == *"Destroy complete!"* ]]; then
    echo "SUCCESS: Terraform destroy of $target completed successfully"
  else
    echo "FAILED: Terraform destroy of $target failed"
    exit 1
  fi
done

#-------------------------------------------
# Terraform destroy full
#-------------------------------------------
terraform destroy -var="acm_certificate_domain=$acm_certificate_domain" -auto-approve
destroy_output=$(terraform destroy -var="acm_certificate_domain=$acm_certificate_domain" -auto-approve 2>&1)
if [[ $? -eq 0 && $destroy_output == *"Destroy complete!"* ]]; then
  echo "SUCCESS: Terraform destroy of all targets completed successfully"
else
  echo "FAILED: Terraform destroy of all targets failed"
  exit 1
fi
