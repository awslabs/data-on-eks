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
