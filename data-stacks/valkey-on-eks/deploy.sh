#!/bin/bash

set -e

# --- Configuration ---
STACKS="valkey-on-eks"
TERRAFORM_DIR="terraform"
AWS_REGION="${AWS_REGION:-us-west-2}"
KUBECONFIG_FILE="kubeconfig.yaml"


# --- Get Repo Root ---
REPO_PATH=$(git rev-parse --show-toplevel)

# --- Source and Execute the Main Deployment Engine ---
# The centralized install.sh handles all the heavy lifting:
#   - copies infra/terraform (base) into terraform/_local
#   - overlays data-stacks/valkey-on-eks/terraform/ on top
#   - runs the staged Terraform apply (VPC -> EKS -> remaining addons)
source $REPO_PATH/infra/terraform/install.sh

# --- Post-Deployment Steps ---
# Steps specific to this stack can be added here.
print_status "Running stack-specific post-deployment steps..."

# Backup the state file from the _local directory
cp "$TERRAFORM_DIR/_local/terraform.tfstate" "$TERRAFORM_DIR/terraform.tfstate.bak"
print_status "Backed up terraform.tfstate."

# Setup kubeconfig
setup_kubeconfig

# Get ArgoCD admin password
export KUBECONFIG=$KUBECONFIG_FILE
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

print_next_steps

# --- Valkey-Specific Next Steps ---
echo ""
echo "========================================="
echo "Valkey Quick Start"
echo "========================================="
echo "Topology: 1 primary + 3 replicas (replication mode)"
echo "Chart   : valkey-io/valkey-helm (official, https://valkey.io/valkey-helm/)"
echo ""
echo "1. Watch the Valkey pods come up (4 pods total):"
echo "   export KUBECONFIG=$KUBECONFIG_FILE"
echo "   kubectl get pods -n valkey -w"
echo ""
echo "2. Once all 4 pods are 2/2 Running, deploy the example workload"
echo "   (write to primary, read from valkey-read load-balanced replicas):"
echo "   kubectl apply -f examples/valkey-cluster.yaml"
echo ""
echo "3. Verify replication health:"
echo "   PASS=\$(kubectl -n valkey get secret valkey-auth -o jsonpath='{.data.default}' | base64 -d)"
echo "   kubectl exec -n valkey valkey-0 -c valkey -- \\"
echo "     valkey-cli -a \"\$PASS\" --no-auth-warning INFO replication"
echo ""
echo "Endpoints:"
echo "   Write : valkey.valkey.svc.cluster.local:6379"
echo "   Read  : valkey-read.valkey.svc.cluster.local:6379"
echo "========================================"
