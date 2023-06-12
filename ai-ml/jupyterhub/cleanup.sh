#!/bin/bash
set -o errexit
set -o pipefail

read -p "Enter acm certificate: " acm_certificate_domain

targets=(
  "module.kubernetes_data_addons"
  "module.eks_blueprints_kubernetes_addons"
  "aws_eks_addon.vpc_cni"
  "module.vpc_cni_irsa"
  "module.ebs_csi_driver_irsa"
  "module.eks"
  "aws_efs_file_system.efs"
  "aws_efs_mount_target.efs_mt"
  "aws_security_group.efs"
  "aws_efs_file_system.efs_shared"
  "aws_efs_mount_target.efs_mt_shared"
  "aws_security_group.efs_shared"
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
