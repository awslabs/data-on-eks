#!/bin/bash
# =============================================================================
# Ray Batch Inference Example - Cleanup
# =============================================================================
# Deletes everything the deploy.sh workflow created on the CLUSTER:
#   - RayService (deepseek-r1-8b) and its Ray cluster / GPU workers
#   - Batch RayJobs (ticket-batch-endpoint, ticket-batch-native)
#   - Ticket generator Job and script ConfigMaps
#   - One-off staging/mirror Jobs (if still present) and the ECR token secret
#
# Deliberately KEPT (one-time artifacts, reusable across deployments):
#   - Model weights in s3://$S3_BUCKET/models/
#   - Generated tickets + results under s3://$S3_BUCKET/ray-batch-inference/
#   - The mirrored ray-llm image in ECR
#
# GPU nodes are released automatically: once the Ray pods are gone, Karpenter
# consolidates the empty nodes (consolidateAfter: 15m on the gpu nodepool).
#
# Usage: ./cleanup.sh [-y]   (-y skips the confirmation prompt)
# =============================================================================

set -uo pipefail

NAMESPACE="raydata"
GREEN='\033[0;32m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $1"; }

if [[ "${1:-}" != "-y" ]]; then
  read -p "Delete all ray-batch-inference cluster resources in namespace '$NAMESPACE'? (y/N): " -n 1 -r; echo
  [[ $REPLY =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 0; }
fi

info "Deleting RayJobs (batch pipelines)..."
kubectl delete rayjob ticket-batch-endpoint ticket-batch-native \
  -n "$NAMESPACE" --ignore-not-found

info "Deleting RayService (inference endpoint + Ray cluster)..."
kubectl delete rayservice deepseek-r1-8b -n "$NAMESPACE" --ignore-not-found

info "Deleting ticket generator..."
kubectl delete job ticket-generator -n "$NAMESPACE" --ignore-not-found
kubectl delete deployment ticket-generator -n "$NAMESPACE" --ignore-not-found
kubectl delete cronjob ticket-generator -n "$NAMESPACE" --ignore-not-found

info "Deleting one-off Jobs (model staging / image mirror, if present)..."
kubectl delete job model-staging-deepseek-r1-8b mirror-ray-llm-image \
  -n "$NAMESPACE" --ignore-not-found

info "Deleting Ray metrics PodMonitor..."
kubectl delete podmonitor ray-batch-inference -n "$NAMESPACE" --ignore-not-found

info "Deleting script ConfigMaps and ECR token secret..."
kubectl delete configmap ticket-generator-script \
  ticket-batch-endpoint-script ticket-batch-native-script \
  -n "$NAMESPACE" --ignore-not-found
kubectl delete secret ecr-push-token -n "$NAMESPACE" --ignore-not-found

info "Waiting for Ray pods to terminate..."
kubectl wait --for=delete pod -l 'ray.io/is-ray-node=yes' -n "$NAMESPACE" \
  --timeout=180s 2>/dev/null || true

echo ""
info "Cluster resources removed. Remaining pods in $NAMESPACE:"
kubectl get pods -n "$NAMESPACE" 2>/dev/null || true
echo ""
info "Kept (one-time artifacts): model weights in S3 (models/),"
info "the Iceberg table (Glue: raydata_spark_logs.support_tickets),"
info "results in S3 (ray-batch-inference/), ray-llm image in ECR."
info "GPU nodes will be reclaimed by Karpenter within ~15 minutes."
