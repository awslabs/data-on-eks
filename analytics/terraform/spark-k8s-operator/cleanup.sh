#!/bin/bash
set -o errexit
set -o pipefail

read -p "Enter the region: " region
export AWS_DEFAULT_REGION=$region

targets=(
  "module.eks_data_addons"
  "module.eks_blueprints_addons"
  "module.eks"
  "aws_ec2_subnet_cidr_reservation.eks_cidr_reservation_0_65"
  "aws_ec2_subnet_cidr_reservation.eks_cidr_reservation_0_66"
  "aws_ec2_subnet_cidr_reservation.eks_cidr_reservation_0_67"
  "aws_ec2_subnet_cidr_reservation.eks_cidr_reservation_1_65"
  "aws_ec2_subnet_cidr_reservation.eks_cidr_reservation_1_66"
  "aws_ec2_subnet_cidr_reservation.eks_cidr_reservation_1_67"
  "module.vpc_endpoints"
  "module.vpc_endpoints_sg"
  "module.vpc"
)

for target in "${targets[@]}"
do
  terraform destroy -target="$target" -auto-approve
  destroy_output=$(terraform destroy -target="$target" -auto-approve 2>&1)
  if [[ $? -eq 0 && $destroy_output == *"Destroy complete!"* ]]; then
    echo "SUCCESS: Terraform destroy of $target completed successfully"
  else
    echo "FAILED: Terraform destroy of $target failed"
    exit 1
  fi
done

terraform destroy -auto-approve
destroy_output=$(terraform destroy -auto-approve 2>&1)
if [[ $? -eq 0 && $destroy_output == *"Destroy complete!"* ]]; then
  echo "SUCCESS: Terraform destroy of all targets completed successfully"
else
  echo "FAILED: Terraform destroy of all targets failed"
  exit 1
fi
