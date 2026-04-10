#!/bin/bash
# Rolling restart of Celeborn workers with configurable delay between restarts
# Usage: ./rolling-restart-celeborn.sh [delay_seconds]
#
# ⚠️  CAUTION: This script uses simple pod deletion without decommission API.
# ⚠️  For production use, prefer the decommission-based approach:
# ⚠️  data-stacks/spark-on-eks/benchmarks/celeborn-benchmarks/rolling-restart-celeborn-with-decommission.sh
#
# This simple approach is acceptable for:
# - Emergency recovery (worker pod stuck/unresponsive)
# - Development/testing environments
# - Quick restarts when decommission API is unavailable
#
# Prerequisites for safe operation:
# - Replication MUST be enabled (spark.celeborn.client.push.replicate.enabled: true)
# - Client retry configuration MUST be set (maxRetriesForEachReplica: 5, retryWait: 15s)
# - Graceful shutdown MUST be enabled (celeborn.worker.graceful.shutdown.enabled: true)
# - All 4 worker ports MUST be fixed (rpc, fetch, push, replicate)
#
# Without these prerequisites, this script WILL cause job failures!

set -e

KUBECONFIG="${KUBECONFIG:-kubeconfig.yaml}"
NAMESPACE="celeborn"
STATEFULSET="celeborn-worker"
DELAY_SECONDS="${1:-120}"  # Default 2 minutes

echo "Starting rolling restart of $STATEFULSET in $NAMESPACE namespace"
echo "Delay between restarts: ${DELAY_SECONDS}s"
echo ""

# Get the number of replicas
REPLICAS=$(kubectl get statefulset $STATEFULSET -n $NAMESPACE -o jsonpath='{.spec.replicas}')
echo "Total replicas: $REPLICAS"
echo ""

# Restart pods in reverse order (highest ordinal first)
for ((i=$REPLICAS-1; i>=0; i--)); do
  POD_NAME="${STATEFULSET}-${i}"

  echo "[$((REPLICAS-i))/$REPLICAS] Restarting $POD_NAME..."

  # Delete the pod
  kubectl delete pod $POD_NAME -n $NAMESPACE --wait=false

  # Wait for pod to be recreated and become Ready
  echo "  Waiting for $POD_NAME to be Ready..."
  kubectl wait pod/$POD_NAME -n $NAMESPACE --for=condition=Ready --timeout=300s

  if [ $? -eq 0 ]; then
    echo "  ✓ $POD_NAME is Ready"
  else
    echo "  ✗ $POD_NAME failed to become Ready within timeout"
    exit 1
  fi

  # Add delay before next restart (skip for last pod)
  if [ $i -gt 0 ]; then
    echo "  Waiting ${DELAY_SECONDS}s before next restart..."
    sleep $DELAY_SECONDS
    echo ""
  fi
done

echo ""
echo "✓ Rolling restart completed successfully"
echo ""
echo "Final status:"
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/role=worker
