#!/bin/bash
# ============================================================
# setup_benchmark.sh — One-time setup for EKS PCP benchmark
#
# Steps:
#   1. Build & push multi-arch Docker image to ECR (with SOCI)
#   2. Upload pod templates to S3
#   3. Apply Prometheus recording rules / alerts
#   4. Print Locust run command
#
# Prerequisites:
#   docker buildx, aws cli v2, kubectl, jq
#   docker buildx builder with QEMU (for cross-arch arm64 build):
#     docker buildx create --use
#     docker run --privileged --rm tonistiigi/binfmt --install all
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TERRAFORM_DIR="$STACK_DIR/terraform/_local"
EMR_TEAM="${EMR_TEAM:-emr-data-team-a}"
CONFIG_FILE="${BENCHMARK_CONFIG_FILE:-$SCRIPT_DIR/benchmark.env}"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "ERROR: benchmark config file not found: $CONFIG_FILE" >&2
  echo "Create it from $SCRIPT_DIR/benchmark.env.example" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

REGION="${AWS_REGION:-}"
IMAGE_TAG="${ECR_IMAGE:-}"
EMR_BASE_IMAGE="${EMR_BASE_IMAGE:-}"
TARGET_REGISTRY="${IMAGE_TAG%%/*}"
BASE_REGISTRY="${EMR_BASE_IMAGE%%/*}"

require_value() {
  local name="$1"
  local value="$2"
  if [[ -z "$value" || "$value" == "null" ]]; then
    echo "ERROR: unable to resolve $name." >&2
    exit 1
  fi
}

# ------------------------------------------------------------------
# Terraform outputs
# ------------------------------------------------------------------
echo "Reading Terraform outputs..."
cd "$TERRAFORM_DIR"
EMR_OUTPUT_JSON="$(terraform output -json emr_on_eks)"
EMR_VIRTUAL_CLUSTER_ID=$(jq -r --arg team "$EMR_TEAM" '
  if has("virtual_clusters") then
    .virtual_clusters[$team].id
  else
    .[$team].virtual_cluster_id
  end
' <<<"$EMR_OUTPUT_JSON")
EMR_EXECUTION_ROLE_ARN=$(jq -r --arg team "$EMR_TEAM" '
  if has("job_execution_role_arns") then
    .job_execution_role_arns[$team]
  else
    .[$team].job_execution_role_arn
  end
' <<<"$EMR_OUTPUT_JSON")
CW_LOG_GROUP=$(jq -r --arg team "$EMR_TEAM" '
  if has("cloudwatch_log_groups") then
    .cloudwatch_log_groups[$team].name
  else
    .[$team].cloudwatch_log_group_name
  end
' <<<"$EMR_OUTPUT_JSON")
S3_BUCKET="s3://$(terraform output -raw emr_s3_bucket_name)"
cd "$SCRIPT_DIR"

require_value "EMR virtual cluster ID" "$EMR_VIRTUAL_CLUSTER_ID"
require_value "EMR execution role ARN" "$EMR_EXECUTION_ROLE_ARN"
require_value "CloudWatch log group" "$CW_LOG_GROUP"
require_value "AWS region" "$REGION"
require_value "Benchmark image" "$IMAGE_TAG"
require_value "EMR base image" "$EMR_BASE_IMAGE"
require_value "TPCDS input" "${TPCDS_INPUT:-}"

SCRIPTS_S3_PATH="${S3_BUCKET}/pcp-benchmarks/scripts"
EMR_ENDPOINT_URL="https://emr-containers-gamma.${REGION}.amazonaws.com"

echo ""
echo "=== EKS PCP Benchmark Setup ==="
echo "  EMR Cluster   : $EMR_VIRTUAL_CLUSTER_ID"
echo "  EMR Team      : $EMR_TEAM"
echo "  S3 Bucket     : $S3_BUCKET"
echo "  Scripts path  : $SCRIPTS_S3_PATH"
echo "  EMR Endpoint  : $EMR_ENDPOINT_URL"
echo "  ECR Image     : $IMAGE_TAG"
echo ""

# ------------------------------------------------------------------
# Step 1: Build & push multi-arch image
# ------------------------------------------------------------------
echo "[1/4] Building and pushing multi-arch image to ECR..."

# Login to the target ECR registry.
aws ecr get-login-password --region "$REGION" | \
  docker login --username AWS --password-stdin "$TARGET_REGISTRY"

# If the base image also lives in private ECR, log into that registry too.
if [[ "$BASE_REGISTRY" == *".amazonaws.com" && "$BASE_REGISTRY" != "$TARGET_REGISTRY" ]]; then
  aws ecr get-login-password --region "$REGION" | \
    docker login --username AWS --password-stdin "$BASE_REGISTRY"
fi

# Enable SOCI enhanced scanning (creates SOCI indexes on every push)
echo "  Enabling SOCI enhanced scanning on ECR repository..."
aws ecr put-registry-scanning-configuration \
  --scan-type ENHANCED \
  --rules "[{\"repositoryFilters\":[{\"filter\":\"emr-eks-tpcds-benchmark\",\"filterType\":\"WILDCARD\"}],\"scanFrequency\":\"SCAN_ON_PUSH\"}]" \
  --region "$REGION" 2>/dev/null || \
  echo "  (enhanced scanning already configured or insufficient permissions — continuing)"

# Build and push (QEMU handles arm64 cross-compilation automatically)
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --build-arg EMR_BASE_IMAGE="$EMR_BASE_IMAGE" \
  --tag "$IMAGE_TAG" \
  --push \
  "$SCRIPT_DIR"

echo "  Image pushed: $IMAGE_TAG"

# ------------------------------------------------------------------
# Step 2: Upload pod templates to S3
# ------------------------------------------------------------------
echo "[2/4] Uploading pod templates to S3..."
aws s3 cp "$SCRIPT_DIR/driver-pod-template.yaml"   "${SCRIPTS_S3_PATH}/driver-pod-template.yaml"
aws s3 cp "$SCRIPT_DIR/executor-pod-template.yaml" "${SCRIPTS_S3_PATH}/executor-pod-template.yaml"
echo "  Uploaded to $SCRIPTS_S3_PATH"

# ------------------------------------------------------------------
# Step 3: Apply Prometheus rules
# ------------------------------------------------------------------
echo "[3/4] Applying Prometheus PCP rules..."
if kubectl get namespace kube-prometheus-stack &>/dev/null; then
  kubectl apply -f "$SCRIPT_DIR/prometheus-pcp-rules.yaml"
  echo "  Prometheus rules applied."
else
  echo "  WARNING: 'kube-prometheus-stack' namespace not found — skipping."
  echo "  Apply manually: kubectl apply -f prometheus-pcp-rules.yaml"
fi

# ------------------------------------------------------------------
# Step 4: Print next steps
# ------------------------------------------------------------------
echo ""
echo "[4/4] Setup complete."
echo ""
echo "--- Test-1 (single-job smoke test) ---"
echo "  ./benchmark.sh start"
echo ""
echo "--- Locust load test ---"
echo "  pip install locust boto3"
echo ""
echo "  export EMR_VIRTUAL_CLUSTER_ID=$EMR_VIRTUAL_CLUSTER_ID"
echo "  export EMR_EXECUTION_ROLE_ARN=$EMR_EXECUTION_ROLE_ARN"
echo "  export OUTPUT_BUCKET=$S3_BUCKET"
echo "  export SCRIPTS_S3_PATH=$SCRIPTS_S3_PATH"
echo "  export TPCDS_INPUT=$TPCDS_INPUT"
echo "  export CW_LOG_GROUP=$CW_LOG_GROUP"
echo ""
echo "  # Port-forward Prometheus for PCP metric monitoring (optional):"
echo "  # kubectl port-forward -n kube-prometheus-stack svc/kube-prometheus-stack-prometheus 9090 &"
echo "  # export PROMETHEUS_URL=http://localhost:9090"
echo ""
echo "  # Ramp to 50 concurrent jobs, 2 users/sec, run 30 min:"
echo "  locust -f locustfile.py --headless -u 50 -r 2 --run-time 30m \\"
echo "         --csv=results/pcp-4xl-\$(date +%Y%m%d-%H%M)"
