#!/bin/bash

set -e

# Configuration
BLUEPRINT_NAME="trino-on-eks"
CLUSTER_NAME="trino-cluster-20250925-1309"
TERRAFORM_DIR="terraform"
AWS_REGION="${AWS_REGION:-us-west-2}"

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

# Deploy infrastructure
deploy_base_infrastructure() {
    print_status "Deploying $BLUEPRINT_NAME infrastructure..."

    cd $TERRAFORM_DIR

    # Initialize Terraform
    print_status "Initializing Terraform..."
    terraform init

    # Plan and deploy VPC and EKS first
    print_status "Planning VPC and EKS deployment..."
    terraform plan -target=module.vpc -target=module.eks

    print_status "Deploying VPC and EKS cluster..."
    terraform apply -target=module.vpc -target=module.eks -auto-approve

    # Update kubeconfig
    print_status "Updating kubeconfig..."
    aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME

}

# Deploy infrastructure
deploy_addons() {
    print_status "Deploying $BLUEPRINT_NAME ArgoCD Addons..."

    # Deploy remaining resources
    print_status "Deploying remaining resources and ArgoCD Addons..."
    terraform apply -auto-approve

    cd ..
}

# Wait for ArgoCD to be ready
wait_for_argocd() {
    print_status "Waiting for ArgoCD to be ready..."

    kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-repo-server -n argocd
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-applicationset-controller -n argocd

    print_status "ArgoCD is ready"
}

# Get ArgoCD credentials
get_argocd_credentials() {
    print_status "Getting ArgoCD credentials..."

    # Get initial admin password
    ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

    echo ""
    echo "========================================="
    echo "ArgoCD Access Information"
    echo "========================================="
    echo "Username: admin"
    echo "Password: $ARGOCD_PASSWORD"
    echo ""
    echo "To access ArgoCD UI:"
    echo "kubectl port-forward svc/argocd-server -n argocd 8081:443"
    echo "Then open: https://localhost:8081"
    echo "(Accept the self-signed certificate)"
    echo "========================================="
    echo ""
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

    echo "Trino Status:"
    kubectl get pods -n trino 2>/dev/null || echo "Trino not yet deployed"
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
    echo "   Password: (shown above)"
    echo ""
    echo "3. Monitor application sync status:"
    echo "   kubectl get applications -n argocd"
    echo ""
    echo "4. Port-forward Trino UI:"
    echo "   kubectl port-forward -n trino service/trino 8080:8080"
    echo ""
    echo "5. Connect with Trino CLI:"
    echo "   ./trino http://127.0.0.1:8080 --user admin"
    echo ""
    echo "6. Run example Hive queries:"
    echo "   cd examples"
    echo "   ./hive-setup.sh"
    echo ""
    echo "7. Clean up (when done):"
    echo "   terraform destroy -auto-approve"
    echo "========================================"
}

print_status "Starting $BLUEPRINT_NAME deployment..."

check_prerequisites

# Copy base infrastructure files
mkdir -p ./terraform/_local
cp -r ../../infra/terraform/* ./terraform/_local/

# Apply blueprint files (overwriting matching files)
tar -C ./terraform --exclude='_local' --exclude='*.tfstate*' --exclude='.terraform' -cf - . | tar -C ./terraform/_local -xf -

cd terraform/_local
source ./install.sh
cp terraform.tfstate ../../terraform.tfstate.bak