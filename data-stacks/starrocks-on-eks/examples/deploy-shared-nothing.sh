#!/bin/bash
#
# Deploy StarRocks Shared-Nothing Cluster
#
# This script applies the shared-nothing cluster manifest directly.
# No Terraform output substitution needed — shared-nothing uses local EBS, not S3.
#
# Usage:
#   cd data-stacks/starrocks-on-eks
#   ./examples/deploy-shared-nothing.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$SCRIPT_DIR/starrocks-shared-nothing.yaml"

echo "=== Deploying StarRocks Shared-Nothing Cluster ==="

# --- Validate prerequisites ---
if ! command -v kubectl &> /dev/null; then
  echo "ERROR: kubectl is not installed or not in PATH"
  exit 1
fi

if ! kubectl cluster-info &> /dev/null; then
  echo "ERROR: kubectl is not configured or the cluster is unreachable"
  echo "Hint: export KUBECONFIG=terraform/_local/kubeconfig.yaml"
  exit 1
fi

if [ ! -f "$MANIFEST" ]; then
  echo "ERROR: Manifest not found at $MANIFEST"
  exit 1
fi

# --- Apply manifest ---
echo "Applying shared-nothing cluster manifest..."
kubectl apply -f "$MANIFEST" || {
  echo "ERROR: kubectl apply failed"
  exit 1
}

echo ""
echo "=== StarRocks Shared-Nothing Cluster deployed ==="
echo ""
echo "Monitor progress:"
echo "  kubectl get pods -n starrocks -w"
echo ""
echo "Connect (via port-forward):"
echo "  kubectl port-forward svc/starrocks-shared-nothing-fe-service 9030:9030 -n starrocks"
echo "  mysql -h 127.0.0.1 -P 9030 -u root"
