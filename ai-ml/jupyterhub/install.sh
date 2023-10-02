#!/bin/bash

read -p "Enter Jupyter Auth mechanism, accepted values are 'dummy' or 'cognito': " jupyter_auth

acm_certificate_domain=""
jupyterhub_domain=""

if [ "$jupyter_auth" == "cognito" ]; then
  read -p "Enter domain name with wildcard and ensure ACM certificate is created for this domain name, e.g. *.example.com :" acm_certificate_domain
  read -p "Enter sub-domain name for jupyterhub to be hosted,  e.g. eks.example.com : " jupyterhub_domain
fi

read -p "Enable GPU on Notebook instances? (y/n) " gpu_notebook

if [ $gpu_notebook == "y" ]; then
  gpu_notebook="gpu"
else
  gpu_notebook="cpu"
fi

# Print all variables above using echo
echo "Jupyter Auth mechanism: $jupyter_auth"
echo "ACM certificate domain: $acm_certificate_domain"
echo "Jupyterhub domain: $jupyterhub_domain"
echo "GPU Notebook: $gpu_notebook"


echo "Initializing ..."
terraform init || echo "\"terraform init\" failed"

# List of Terraform modules to apply in sequence
targets=(
  "module.vpc"
  "module.eks"
  "module.ebs_csi_driver_irsa"
  "module.eks_blueprints_addons"
)

# Apply modules in sequence
for target in "${targets[@]}"
do
  echo "Applying module $target..."
  apply_output=$(terraform apply -target="$target" -var="acm_certificate_domain=$acm_certificate_domain" -var="jupyterhub_domain=$jupyterhub_domain" -var="jupyter_hub_auth_mechanism=$jupyter_auth" -var="jupyter_notebook_support=$gpu_notebook" -auto-approve 2>&1 | tee /dev/tty)
  if [[ ${PIPESTATUS[0]} -eq 0 && $apply_output == *"Apply complete"* ]]; then
    echo "SUCCESS: Terraform apply of $target completed successfully"
  else
    echo "FAILED: Terraform apply of $target failed"
    exit 1
  fi
done

# Final apply to catch any remaining resources
echo "Applying remaining resources..."
apply_output=$(terraform apply -var="acm_certificate_domain=$acm_certificate_domain" -var="jupyterhub_domain=$jupyterhub_domain" -var="jupyter_hub_auth_mechanism=$jupyter_auth" -var="jupyter_notebook_support=$gpu_notebook" -auto-approve 2>&1 | tee /dev/tty)
if [[ ${PIPESTATUS[0]} -eq 0 && $apply_output == *"Apply complete"* ]]; then
  echo "SUCCESS: Terraform apply of all modules completed successfully"
else
  echo "FAILED: Terraform apply of all modules failed"
  exit 1
fi
