#!/bin/bash
#
# Deploy StarRocks Shared-Data Cluster
#
# This script retrieves S3 bucket and region from Terraform outputs,
# substitutes placeholders in the shared-data manifest, and applies it.
#
# Usage:
#   cd data-stacks/starrocks-on-eks
#   ./examples/deploy-shared-data.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$SCRIPT_DIR/starrocks-shared-data.yaml"
TERRAFORM_DIR="$SCRIPT_DIR/../terraform/_local"

echo "=== Deploying StarRocks Shared-Data Cluster ==="

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

# --- Retrieve Terraform outputs ---
echo "Retrieving S3 bucket ID from Terraform outputs..."
S3_BUCKET_ID=$(terraform -chdir="$TERRAFORM_DIR" output -raw starrocks_s3_bucket_id 2>/dev/null) || {
  echo "ERROR: Failed to retrieve 'starrocks_s3_bucket_id' from Terraform outputs"
  echo "Hint: Ensure deploy.sh has been run and enable_starrocks=true"
  exit 1
}

echo "Retrieving AWS region from Terraform outputs..."
REGION=$(terraform -chdir="$TERRAFORM_DIR" output -raw region 2>/dev/null) || {
  echo "ERROR: Failed to retrieve 'region' from Terraform outputs"
  exit 1
}

echo "  S3 Bucket: $S3_BUCKET_ID"
echo "  Region:    $REGION"

# --- Substitute placeholders and apply ---
echo "Applying shared-data cluster manifest..."
sed \
  -e "s|<STARROCKS_S3_BUCKET_ID>|${S3_BUCKET_ID}|g" \
  -e "s|<REGION>|${REGION}|g" \
  "$MANIFEST" | kubectl apply -f - || {
  echo "ERROR: kubectl apply failed"
  exit 1
}

echo ""
echo "=== StarRocks Shared-Data Cluster deployed ==="
echo ""
echo "Monitor progress:"
echo "  kubectl get pods -n starrocks -w"
echo ""
echo "Connect (via NLB):"
echo "  NLB=\$(kubectl get svc starrocks-shared-data-fe-service -n starrocks -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
echo "  mysql -h \$NLB -P 9030 -u root"
