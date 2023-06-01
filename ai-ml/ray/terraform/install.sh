#!/bin/bash
set -o errexit
set -o pipefail

echo "Running terraform init..."
terraform init -upgrade > /dev/null 2>&1

echo "Creating VPC..."
terraform apply -target=module.vpc -auto-approve || exit 1

echo "Creating Karpenter Policy..."
terraform apply -target=module.karpenter_policy -auto-approve || exit 1

echo "Creating Redis (MemoryDb)..."
terraform apply -target=module.memory_db -auto-approve || exit 1

echo "Creating EKS Cluster..."
#terraform apply -target=module.eks -target=kubectl_manifest.eni_config -auto-approve || exit 1
terraform apply -target=module.eks -auto-approve || exit 1

echo "Creating AddOns..."
terraform apply -target=module.eks_blueprints_addons -auto-approve || exit 1

echo "Creating everything else..."
terraform apply -auto-approve || exit 1