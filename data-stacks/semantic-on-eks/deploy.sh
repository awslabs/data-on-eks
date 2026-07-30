#!/bin/bash

set -e

# --- Configuration ---
STACKS="semantic-on-eks"
TERRAFORM_DIR="terraform"
AWS_REGION="${AWS_REGION:-us-west-2}"
KUBECONFIG_FILE="kubeconfig.yaml"


# --- Get Repo Root ---
REPO_PATH=$(git rev-parse --show-toplevel)

# --- Source and Execute the Main Deployment Engine ---
source $REPO_PATH/infra/terraform/install.sh

# --- Post-Deployment Steps ---
print_status "Running stack-specific post-deployment steps..."

# Backup the state file from the _local directory
cp "$TERRAFORM_DIR/_local/terraform.tfstate" "$TERRAFORM_DIR/terraform.tfstate.bak"
print_status "Backed up terraform.tfstate."

# Setup kubeconfig
setup_kubeconfig

# --- Deployment Summary ---
# Show the user exactly what was deployed for this stack.
print_stack_summary() {
    local kc="$TERRAFORM_DIR/_local/$KUBECONFIG_FILE"
    [ -f "$kc" ] || kc="$KUBECONFIG_FILE"

    echo ""
    echo "=================================================================="
    echo " semantic-on-eks — Deployment Summary"
    echo "=================================================================="

    echo ""
    echo "--- Cluster nodes (by NodeGroupType) ---"
    kubectl --kubeconfig "$kc" get nodes -L NodeGroupType 2>/dev/null

    echo ""
    echo "--- ArgoCD applications (sync / health) ---"
    kubectl --kubeconfig "$kc" get applications -n argocd \
      -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status \
      2>/dev/null

    echo ""
    echo "--- Stack workload pods ---"
    for ns in trino polaris datahub valkey; do
        echo "  [$ns]"
        kubectl --kubeconfig "$kc" get pods -n "$ns" --no-headers 2>/dev/null \
          | awk '{printf "    %-45s %s\n", $1, $3}' || echo "    (namespace not ready yet)"
    done

    echo ""
    echo "--- Access endpoints (via kubectl port-forward) ---"
    echo "  Trino     : kubectl -n trino  port-forward svc/trino          8080:8080  -> http://localhost:8080/ui"
    echo "  Polaris   : kubectl -n polaris port-forward svc/polaris        8181:8181  -> http://localhost:8181"
    echo "  DataHub   : kubectl -n datahub port-forward svc/datahub-datahub-frontend 9002:9002 -> http://localhost:9002"
    echo "=================================================================="
}

print_stack_summary
print_next_steps
