#!/bin/bash

echo "Initializing ..."

# Initialize Terraform
terraform init -upgrade

# Check logic
# 1. if TF_VAR_enable_nvidia_triton_server not specifically set to false; when customer just enabled NIM pattern, we should not check the huggingface_token
# 2. if TF_VAR_enable_nvidia_triton_server is explicitly set to true, check the huggingface_token
# 3. if TF_VAR_enable_nvidia_triton_server is empty, still check the huggingface_token token, as it's the default behaviour.
if [[ "${TF_VAR_enable_nvidia_triton_server}" != "false" || "${TF_VAR_enable_nvidia_triton_server}" == "true" || -z "${TF_VAR_enable_nvidia_triton_server}" ]]; then
  echo "Triton server enabled..."
  if [[ -z "${TF_VAR_huggingface_token}" ]]; then
    echo "FAILED: TF_VAR_huggingface_token environment variable is not set"
    exit 1
  fi

  if [[ "${TF_VAR_huggingface_token}" = "DUMMY_TOKEN_REPLACE_ME" ]]; then
    echo "FAILED: Please replace dummy HuggingFace Token before proceeding"
    exit 1
  fi
fi

if [ "$TF_VAR_enable_nvidia_nim" = true ]; then
  # Check if server_token does not start with "nvapi-"
  # Obtain your NVIDIA NGC API key from https://docs.nvidia.com/nim/large-language-models/latest/getting-started.html#generate-an-api-key
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
for target in "${targets[@]}"; do
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
