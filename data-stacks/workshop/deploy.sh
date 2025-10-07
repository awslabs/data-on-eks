#!/bin/bash

set -e

# Configuration
BLUEPRINT_NAME="spark-operator"
TERRAFORM_DIR="terraform"
AWS_REGION="${AWS_REGION:-us-east-1}"
KUBECONFIG_FILE="kubeconfig"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."

    command -v terraform >/dev/null 2>&1 || { print_error "terraform is required but not installed."; exit 1; }
    command -v kubectl >/dev/null 2>&1 || { print_error "kubectl is required but not installed."; exit 1; }
    command -v aws >/dev/null 2>&1 || { print_error "aws cli is required but not installed."; exit 1; }

    # Check AWS credentials
    aws sts get-caller-identity >/dev/null 2>&1 || { print_error "AWS credentials not configured."; exit 1; }

    print_status "Prerequisites check passed"
}

# Verify deployment
verify_deployment() {
    print_status "Verifying deployment..."

    echo ""
    echo "========================================="
    echo "Cluster Information"
    echo "========================================="
    kubectl get nodes
    echo ""

    echo "ArgoCD Applications:"
    kubectl get applications -n argocd
    echo ""

    echo "Spark Operator Status:"
    kubectl get pods -n spark-operator 2>/dev/null || echo "Spark operator not yet deployed"
    echo ""

    echo "Karpenter Status:"
    kubectl get pods -n karpenter 2>/dev/null || echo "Karpenter not yet deployed"
    echo ""
}

# Print next steps
print_next_steps() {
    echo ""
    echo "========================================="
    echo "Next Steps"
    echo "========================================="
    echo "1. Port-forward ArgoCD:"
    echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
    echo ""
    echo "2. Access ArgoCD UI at https://localhost:8080"
    echo "   Username: admin"
    echo "   Password: $ARGOCD_PASSWORD"
    echo ""
    echo "3. Monitor application sync status:"
    echo "   kubectl get applications -n argocd"
    echo ""
    echo "4. Clean up (when done):"
    echo "   ./cleaup.sh"
    echo "========================================"
}

setup_kubeconfig() {
    print_status "Setting up kubeconfig..."
    
    local cluster_name
    cluster_name=$(terraform -chdir="$TERRAFORM_DIR/_local" output -raw cluster_name)
    
    if [ -z "$cluster_name" ]; then
        echo "Could not get cluster name from terraform output."
        exit 1
    fi
    
    print_status "Found cluster: $cluster_name"
    
    aws eks update-kubeconfig --name "$cluster_name" --region "${AWS_REGION}" --kubeconfig "$KUBECONFIG_FILE"
    
    print_status "Kubeconfig created at $KUBECONFIG_FILE"
}

print_status "Starting $BLUEPRINT_NAME deployment..."

check_prerequisites

# Generate random deployment_id if needed
# This ID is used to identify and delete AWS resources orphaned by Kubernetes Operators.
TFVARS_FILE="./terraform/blueprint.tfvars"
if [ -f "$TFVARS_FILE" ]; then
    if grep -q 'deployment_id = "abcdefg"' "$TFVARS_FILE"; then
        print_status "Default deployment_id found. Generating a new random one."
        RANDOM_ID=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 8)
        sed -i "s/deployment_id = \"abcdefg\"/deployment_id = \"$RANDOM_ID\"/" "$TFVARS_FILE"
        print_status "Updated deployment_id to $RANDOM_ID in $TFVARS_FILE"
    fi
else
    print_warning "$TFVARS_FILE not found. Skipping deployment_id update."
fi

# Clean up _local directory before copying files
if [ -d "./terraform/_local" ]; then
    print_status "Cleaning up terraform/_local directory..."
    find ./terraform/_local -mindepth 1 -maxdepth 1 -not -name '.terraform' -not -name '.terraform.lock.hcl' -not -name 'terraform.tfstate*' -exec rm -rf {} +
fi

# Copy base infrastructure files
print_status "Copying from the infra folder..."
mkdir -p ./terraform/_local
cp -r ../../infra/terraform/* ./terraform/_local/

# Apply blueprint files (overwriting matching files)
print_status "Overwriting files..."
tar -C ./terraform --exclude='_local' --exclude='*.tfstate*' --exclude='.terraform' -cf - . | tar -C ./terraform/_local -xvf -

cd terraform/_local
source ./install.sh
cp terraform.tfstate ../../terraform.tfstate.bak

cd ../..

setup_kubeconfig
export KUBECONFIG=$KUBECONFIG_FILE
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

print_next_steps