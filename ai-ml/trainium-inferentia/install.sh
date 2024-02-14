
#--------------------------------------------------------------
# Llama2 Distributed Training pre-requisites
#--------------------------------------------------------------
# export TF_VAR_enable_mpi_operator=true
# export TF_VAR_trn1_32xl_min_size=4
# export TF_VAR_trn1_32xl_desired_size=4
#--------------------------------------------------------------

#--------------------------------------------------------------
# BERT-large Distributed Training pre-requisites
#--------------------------------------------------------------
# export TF_VAR_enable_volcano=true
# export TF_VAR_trn1_32xl_min_size=2
# export TF_VAR_trn1_32xl_desired_size=2
#--------------------------------------------------------------

#!/bin/bash

echo "Initializing ..."

terraform init || echo "\"terraform init\" failed"

#-------------------------------------------------------------------------
# List of Terraform modules to apply in sequence
#-------------------------------------------------------------------------
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

##-------------------------------------------------------------------------
