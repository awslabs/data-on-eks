#!/bin/bash

echo "Initializing ..."

# Initialize Terraform
terraform init -upgrade

# validate if env is empty or has dummy value

if [[ -z "${TF_VAR_huggingface_token}" ]]; then
    echo "FAILED: TF_VAR_huggingface_token environment variable is not set"
    exit 1
fi

if [[ "${TF_VAR_huggingface_token}" = "DUMMY_TOKEN_REPLACE_ME" ]] ; then
    echo "FAILED: Please replace dummy HuggingFace Token before proceeding"
    exit 1
fi

if [ "$TF_VAR_enable_nvidia_nim" = true ]; then
    # Check if server_token does not start with "nvapi-"
    # Obtain your NVIDIA NGC API key from https://docs.nvidia.com/ai-enterprise/deployment-guide-spark-rapids-accelerator/0.1.0/appendix-ngc.html
    if [[ ! "$TF_VAR_ngc_api_key" == nvapi-* ]]; then
        echo "FAILED: TF_VAR_ngc_api_key must start with 'nvapi-'"
        exit 1
    fi
fi

echo "Proceed with deployment of targets..."

# List of Terraform modules to apply in sequence
targets=(
  "module.vpc"
  "module.eks"
)

# Apply modules in sequence
for target in "${targets[@]}"
do
  echo "Applying module $target..."
  apply_output=$(terraform apply -target="$target" -auto-approve 2>&1 | tee /dev/tty)
  if [[ ${PIPESTATUS[0]} -eq 0 && $apply_output == *"Apply complete"* ]]; then
    echo "SUCCESS: Terraform apply of $target completed successfully"
  else
    echo "FAILED: Terraform apply of $target failed"
    exit 1
  fi
done

# Final apply to catch any remaining resources
echo "Applying remaining resources..."
apply_output=$(terraform apply -auto-approve 2>&1 | tee /dev/tty)
if [[ ${PIPESTATUS[0]} -eq 0 && $apply_output == *"Apply complete"* ]]; then
  echo "SUCCESS: Terraform apply of all modules completed successfully"
else
  echo "FAILED: Terraform apply of all modules failed"
  exit 1
fi
