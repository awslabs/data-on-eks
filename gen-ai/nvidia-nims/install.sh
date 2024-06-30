#!/bin/bash

# Download the nim-deploy repo
echo "Downloading nim-deploy repo ..."
TEMP_DIR=$(mktemp -d)
git clone https://github.com/NVIDIA/nim-deploy.git "$TEMP_DIR/nim-deploy"
cp -r "$TEMP_DIR/nim-deploy/helm/nim-llm" ./nim-llm
rm -rf "$TEMP_DIR"

echo "Initializing ..."

# Initialize Terraform
terraform init -upgrade

echo "Proceed with deployment of targets..."

List of Terraform modules to apply in sequence
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
