#!/bin/bash
#
# Deploy TPC-DS Data Generation Job
#
# Generates 1TB TPC-DS dataset using parallel dsdgen workers.
# The data is stored on a 1Ti PVC for reuse across benchmark runs.
#
# Configuration (edit tpcds-datagen-1tb.yaml or override here):
#   PARALLEL_WORKERS: Number of concurrent dsdgen processes (default: 32)
#   CPU requests/limits: Should match PARALLEL_WORKERS for full utilization
#   Scale factor: 1000 = ~1TB of raw data
#
# Estimated time: ~30-45 min with 32 workers on a 32-core instance
#
# Usage:
#   cd data-stacks/starrocks-on-eks
#   ./examples/deploy-tpcds-datagen.sh
#
# Monitor:
#   kubectl logs -f job/tpcds-datagen-1tb -n starrocks
#
# Check progress:
#   kubectl exec $(kubectl get pod -l job-name=tpcds-datagen-1tb -n starrocks -o name) \
#     -n starrocks -- du -sh /data/tpcds-1tb/

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$SCRIPT_DIR/tpcds-datagen-1tb.yaml"

echo "=== Deploying TPC-DS 1TB Data Generation Job ==="

# --- Validate prerequisites ---
if ! command -v kubectl &> /dev/null; then
  echo "ERROR: kubectl is not installed or not in PATH"
  exit 1
fi

if ! kubectl cluster-info &> /dev/null; then
  echo "ERROR: kubectl is not configured or the cluster is unreachable"
  exit 1
fi

# --- Clean up any previous run ---
echo "Cleaning up previous runs (if any)..."
kubectl delete job tpcds-datagen-1tb -n starrocks --ignore-not-found=true 2>/dev/null
kubectl delete pvc tpcds-data-pvc -n starrocks --ignore-not-found=true 2>/dev/null

# Wait for PVC deletion to complete
echo "Waiting for cleanup to finish..."
sleep 5

# --- Deploy ---
echo "Applying data generation manifest..."
kubectl apply -f "$MANIFEST" || {
  echo "ERROR: kubectl apply failed"
  exit 1
}

echo ""
echo "=== TPC-DS Data Generation Job deployed ==="
echo ""
echo "Monitor progress:"
echo "  kubectl logs -f job/tpcds-datagen-1tb -n starrocks"
echo ""
echo "Check disk usage:"
echo "  kubectl exec \$(kubectl get pod -l job-name=tpcds-datagen-1tb -n starrocks -o name) -n starrocks -- du -sh /data/tpcds-1tb/"
echo ""
echo "Check CPU usage:"
echo "  kubectl top pod -l job-name=tpcds-datagen-1tb -n starrocks"
