#!/bin/bash
set -o errexit
set -o pipefail

# Make sure you have `terraform.tfvars` file with the desired region.
# Otherwise script will ask you to input your region each time it runs `terraform destroy`

targets=(
  "module.eks_data_addons"
  "module.eks_blueprints_kubernetes_addons"
  "module.vpc_cni_irsa"
  "module.ebs_csi_driver_irsa"
  "module.eks"
  "module.vpc"
)

#-------------------------------------------
# Terraform destroy per module target
#-------------------------------------------
for target in "${targets[@]}"
do
  terraform destroy -target="$target" -auto-approve
done

#-------------------------------------------
# Terraform destroy full
#-------------------------------------------
terraform destroy -auto-approve
