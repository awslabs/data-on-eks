#!/bin/bash
#
# Deploy TPC-DS Data Loader Job
#
# Loads TPC-DS data from the PVC into a target StarRocks cluster.
# The loader creates tables (if not exist) and uses stream_load API.
#
# Usage:
#   cd data-stacks/starrocks-on-eks
#   ./examples/deploy-tpcds-loader.sh shared-data      # Load into shared-data cluster
#   ./examples/deploy-tpcds-loader.sh shared-nothing    # Load into shared-nothing cluster

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$SCRIPT_DIR/tpcds-data-loader.yaml"
TARGET="${1:-shared-data}"

case "$TARGET" in
  shared-data)
    FE_SERVICE="starrocks-shared-data-fe-service"
    ;;
  shared-nothing)
    FE_SERVICE="starrocks-shared-nothing-fe-service"
    ;;
  *)
    echo "Usage: $0 {shared-data|shared-nothing}"
    echo ""
    echo "  shared-data     Load into the shared-data cluster (S3 storage)"
    echo "  shared-nothing  Load into the shared-nothing cluster (EBS storage)"
    exit 1
    ;;
esac

echo "=== Deploying TPC-DS Data Loader ==="
echo "Target cluster: ${TARGET}"
echo "FE service:     ${FE_SERVICE}"

# --- Validate prerequisites ---
if ! command -v kubectl &> /dev/null; then
  echo "ERROR: kubectl is not installed or not in PATH"
  exit 1
fi

if ! kubectl cluster-info &> /dev/null; then
  echo "ERROR: kubectl is not configured or the cluster is unreachable"
  exit 1
fi

# Check PVC exists
if ! kubectl get pvc tpcds-data-pvc -n starrocks &> /dev/null; then
  echo "ERROR: PVC tpcds-data-pvc not found. Run deploy-tpcds-datagen.sh first."
  exit 1
fi

# --- Clean up previous loader run ---
echo "Cleaning up previous loader job (if any)..."
kubectl delete job tpcds-data-loader -n starrocks --ignore-not-found=true 2>/dev/null
sleep 3

# --- Apply with FE_SERVICE override ---
echo "Applying data loader manifest..."
sed "s|starrocks-shared-data-fe-service|${FE_SERVICE}|g" "$MANIFEST" | kubectl apply -f - || {
  echo "ERROR: kubectl apply failed"
  exit 1
}

echo ""
echo "=== TPC-DS Data Loader deployed ==="
echo "Target: ${TARGET} (${FE_SERVICE})"
echo ""
echo "Monitor progress:"
echo "  kubectl logs -f job/tpcds-data-loader -n starrocks"
echo ""
echo "Verify tables after loading:"
echo "  kubectl port-forward svc/${FE_SERVICE} 9030:9030 -n starrocks"
echo "  mysql -h 127.0.0.1 -P 9030 -u root -e 'USE tpcds; SHOW TABLES;'"
