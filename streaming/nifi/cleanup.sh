#!/bin/bash
set -o errexit
set -o pipefail

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

targets=(
  "module.eks_blueprints_kubernetes_addons"
  "module.eks"
)

#-------------------------------------------
# Helpful to delete the stuck in "Terminating" namespaces
# Rerun the cleanup.sh script to detect and delete the stuck resources
#-------------------------------------------
terminating_namespaces=$(kubectl get namespaces --field-selector status.phase=Terminating -o json | jq -r '.items[].metadata.name')

# If there are no terminating namespaces, exit the script
if [[ -z $terminating_namespaces ]]; then
    echo "No terminating namespaces found"
else
  echo "Terminating namespaces:"
  for ns in $terminating_namespaces; do
      case "$choice" in
          y|Y )
              kubectl get namespace $ns -o json | sed 's/"kubernetes"//' | kubectl replace --raw "/api/v1/namespaces/$ns/finalize" -f -
              ;;
          * )
              echo "Skipping namespace $ns"
              ;;
      esac
  done
fi
#-------------------------------------------
# Terraform destroy per module target
#-------------------------------------------
for target in "${targets[@]}"
do
  destroy_output=$(terraform destroy -target="$target" -auto-approve 2>&1)
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
destroy_output=$(terraform destroy -auto-approve 2>&1)
if [[ $? -eq 0 && $destroy_output == *"Destroy complete!"* ]]; then
  echo "SUCCESS: Terraform destroy of all targets completed successfully"
else
  echo "FAILED: Terraform destroy of all targets failed"
  exit 1
fi