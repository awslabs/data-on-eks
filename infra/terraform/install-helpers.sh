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

    # Docker credential helper sanity check.
    # Several charts (e.g. Karpenter) are pulled by Helm from public OCI
    # registries such as oci://public.ecr.aws. Even for anonymous pulls, Helm
    # first invokes the credsStore/credHelper configured in ~/.docker/config.json.
    # If that helper is missing from PATH (common when Docker Desktop is not
    # installed/running), the chart download fails with an opaque
    # "docker-credential-<x>: executable file not found" error. public.ecr.aws
    # allows anonymous pulls, so we neutralize a broken helper for this run.
    check_docker_creds_helper

    print_status "Prerequisites check passed"
}

# Detect a docker credsStore/credHelper that isn't installed and disable it for
# this deployment so anonymous public-OCI (public.ecr.aws) chart pulls succeed.
check_docker_creds_helper() {
    local docker_config="$HOME/.docker/config.json"
    [ -f "$docker_config" ] || return 0
    command -v python3 >/dev/null 2>&1 || return 0

    local helper
    helper=$(python3 -c "import json,sys; print(json.load(open('$docker_config')).get('credsStore',''))" 2>/dev/null)
    [ -n "$helper" ] || return 0

    if ! command -v "docker-credential-$helper" >/dev/null 2>&1; then
        print_warning "Docker credsStore '$helper' is configured but docker-credential-$helper is not on PATH."
        print_warning "This breaks Helm OCI chart pulls (e.g. Karpenter). Disabling it for this deployment."
        cp "$docker_config" "$docker_config.doeks-bak" 2>/dev/null || true
        python3 -c "import json; p='$docker_config'; c=json.load(open(p)); c.pop('credsStore',None); json.dump(c,open(p,'w'),indent=2)" \
            && print_status "Removed broken credsStore from $docker_config (backup: $docker_config.doeks-bak)."
    fi
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
    echo "   ./cleanup.sh"
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

refresh_argocd_apps() {
    print_status "Refreshing all ArgoCD applications..."

    local apps
    apps=$(kubectl --kubeconfig "$KUBECONFIG_FILE" get applications -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name --no-headers)

    if [ -z "$apps" ]; then
        print_warning "No ArgoCD applications found to refresh."
        return
    fi

    echo "$apps" | while read -r namespace name; do
        if [ -n "$namespace" ] && [ -n "$name" ]; then
            kubectl --kubeconfig "$KUBECONFIG_FILE" annotate application "$name" -n "$namespace" argocd.argoproj.io/refresh=hard
        fi
    done

    print_status "Finished adding refresh annotation to all ArgoCD applications."
}
