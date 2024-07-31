#!/bin/bash

read -p "Enter the region: " region
export AWS_DEFAULT_REGION=$region

# List of Terraform modules to apply in sequence
targets=(
  "module.vpc"
  "module.vpc_endpoints_sg"
  "module.vpc_endpoints"
  "aws_ec2_subnet_cidr_reservation.eks_cidr_reservation_0_65"
  "aws_ec2_subnet_cidr_reservation.eks_cidr_reservation_0_66"
  "aws_ec2_subnet_cidr_reservation.eks_cidr_reservation_0_67"
  "aws_ec2_subnet_cidr_reservation.eks_cidr_reservation_1_65"
  "aws_ec2_subnet_cidr_reservation.eks_cidr_reservation_1_66"
  "aws_ec2_subnet_cidr_reservation.eks_cidr_reservation_1_67"
  "module.eks"
)

# Initialize Terraform
terraform init -upgrade

# Apply modules in sequence
for target in "${targets[@]}"
do
  echo "Applying module $target..."
  apply_output=$(terraform apply -target="$target" -var="region=$region" -auto-approve 2>&1 | tee /dev/tty)
  if [[ ${PIPESTATUS[0]} -eq 0 && $apply_output == *"Apply complete"* ]]; then
    echo "SUCCESS: Terraform apply of $target completed successfully"
  else
    echo "FAILED: Terraform apply of $target failed"
    exit 1
  fi
done

# Final apply to catch any remaining resources
echo "Applying remaining resources..."
apply_output=$(terraform apply -var="region=$region" -auto-approve 2>&1 | tee /dev/tty)
if [[ ${PIPESTATUS[0]} -eq 0 && $apply_output == *"Apply complete"* ]]; then
  echo "SUCCESS: Terraform apply of all modules completed successfully"
else
  echo "FAILED: Terraform apply of all modules failed"
  exit 1
fi
