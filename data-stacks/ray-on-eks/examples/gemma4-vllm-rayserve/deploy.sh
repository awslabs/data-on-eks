#!/bin/bash
# =============================================================================
# Gemma 4 12B on RayServe + vLLM - Deployment Helper
# =============================================================================
# Optimized OpenAI-compatible endpoint for google/gemma-4-12B-it on the
# ray-on-eks stack:
#
#   01  Stage Gemma 4 12B safetensors in S3 (from HuggingFace, apache-2.0)
#   02  Mirror a Gemma 4-capable rayproject/ray-llm image to same-region ECR
#   03  RayService: OpenAI-compatible endpoint (vLLM, weights from S3 mirror)
#
# Gemma 4 (model_type gemma4_unified) needs a recent vLLM. The DeepSeek
# example's ray-llm:2.56.0 is TOO OLD; the default $RAY_LLM_TAG below is a
# 2.57.x build. 'prepare' mirrors it to ECR and 'verify' checks the arch is
# registered before you spend a GPU node.
#
# Required environment variables:
#   export S3_BUCKET="ray-on-eks-spark-logs-..."   # data bucket
#   export AWS_REGION="us-west-2"
# Optional overrides:
#   export HF_MODEL_ID="google/gemma-4-12B"        # base instead of -it
#   export MODEL_DIR="gemma-4-12b"                  # S3 subdir / served id base
#   export RAY_LLM_TAG="nightly-py312-cu130"        # if 2.57.x lacks gemma4
#
# Usage:
#   ./deploy.sh prepare     # 01 + 02: stage model, mirror image (run once)
#   ./deploy.sh verify      # confirm the ECR image registers gemma4_unified
#   ./deploy.sh service     # 03: deploy the RayService endpoint
#   ./deploy.sh measure     # deploy fresh + time end-to-end until serving
#   ./deploy.sh test        # send a sample OpenAI chat request
#   ./deploy.sh status      # show everything
#   ./deploy.sh cleanup     # delete the RayService (keeps S3 weights + image)
# =============================================================================

set -euo pipefail

NAMESPACE="raydata"
# A Gemma 4-capable ray-llm build (Ray 2.57.x). Override if a nightly is needed.
RAY_LLM_TAG="${RAY_LLM_TAG:-2.57.0.6c4022-py312-cu130}"
S3_BUCKET="${S3_BUCKET:-}"
AWS_REGION="${AWS_REGION:-us-west-2}"
HF_MODEL_ID="${HF_MODEL_ID:-google/gemma-4-12B-it}"   # download source (staging)
MODEL_DIR="${MODEL_DIR:-gemma-4-12b-it}"              # S3 subdir under models/
MODEL_ID="${MODEL_ID:-$MODEL_DIR}"                    # served id (RayService)
SERVICE_NAME="gemma4-12b"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

require_env() {
  [[ -n "$S3_BUCKET" ]] || fail "export S3_BUCKET=<your data bucket> first (e.g. ray-on-eks-spark-logs-...)."
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text) \
    || fail "AWS credentials invalid/expired - refresh them and retry."
  ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
}

render() {
  sed -e "s|\$S3_BUCKET|$S3_BUCKET|g" \
      -e "s|\$AWS_REGION|$AWS_REGION|g" \
      -e "s|\$ECR_REGISTRY|$ECR_REGISTRY|g" \
      -e "s|\$RAY_LLM_TAG|$RAY_LLM_TAG|g" \
      -e "s|\$HF_MODEL_ID|$HF_MODEL_ID|g" \
      -e "s|\$MODEL_DIR|$MODEL_DIR|g" \
      -e "s|\$MODEL_ID|$MODEL_ID|g" \
      "$1"
}

prepare() {
  require_env
  info "Model: $HF_MODEL_ID  ->  s3://$S3_BUCKET/models/$MODEL_DIR"
  info "Creating ECR repository (idempotent)..."
  aws ecr describe-repositories --repository-names ray-llm --region "$AWS_REGION" >/dev/null 2>&1 \
    || aws ecr create-repository --repository-name ray-llm --region "$AWS_REGION" >/dev/null
  info "Refreshing ECR push token secret..."
  kubectl create secret generic ecr-push-token -n "$NAMESPACE" \
    --from-literal=token="$(aws ecr get-login-password --region "$AWS_REGION")" \
    --dry-run=client -o yaml | kubectl apply -f -
  info "Staging Gemma 4 12B weights in S3 (apache-2.0, no token needed)..."
  kubectl delete job model-staging-gemma4-12b -n "$NAMESPACE" --ignore-not-found
  render 01-model-staging-job.yaml | kubectl apply -f -
  info "Mirroring ray-llm:$RAY_LLM_TAG image to ECR..."
  kubectl delete job mirror-ray-llm-image -n "$NAMESPACE" --ignore-not-found
  render 02-image-mirror-job.yaml | kubectl apply -f -
  info "Watch with: kubectl get pods -n $NAMESPACE -w"
  info "Staging done when job/model-staging-gemma4-12b shows Complete; then './deploy.sh verify'."
}

# Confirm the mirrored image's vLLM actually registers Gemma4 Unified before
# committing a GPU node to it. Runs a short CPU pod on the image.
verify() {
  require_env
  local img="$ECR_REGISTRY/ray-llm:$RAY_LLM_TAG"
  info "Checking $img registers gemma4_unified (CPU pod, ~image pull time)..."
  kubectl delete pod gemma4-vllm-check -n "$NAMESPACE" --ignore-not-found >/dev/null 2>&1
  local pycheck='import vllm, transformers; from vllm import ModelRegistry; archs=set(ModelRegistry.get_supported_archs()); print("vllm", vllm.__version__); print("transformers", transformers.__version__, "(runtime_env upgrades to >=5.10.4 for gemma4_unified config parsing)"); print("gemma4_unified_supported", "Gemma4UnifiedForConditionalGeneration" in archs)'
  kubectl run gemma4-vllm-check -n "$NAMESPACE" --image="$img" --restart=Never \
    --overrides='{"spec":{"nodeSelector":{"kubernetes.io/arch":"amd64"}}}' \
    --command -- python -c "$pycheck" \
    >/dev/null 2>&1 || true
  kubectl wait --for=condition=Ready pod/gemma4-vllm-check -n "$NAMESPACE" --timeout=600s 2>/dev/null || true
  # The pod is short-lived; poll logs until it completes.
  for _ in $(seq 1 60); do
    phase=$(kubectl get pod gemma4-vllm-check -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    [[ "$phase" == "Succeeded" || "$phase" == "Failed" ]] && break
    sleep 5
  done
  echo "----- image capability check -----"
  kubectl logs gemma4-vllm-check -n "$NAMESPACE" 2>&1 || true
  echo "----------------------------------"
  kubectl delete pod gemma4-vllm-check -n "$NAMESPACE" --ignore-not-found >/dev/null 2>&1
  warn "If gemma4_unified_supported is False, set RAY_LLM_TAG=nightly-py312-cu130, re-run prepare, and verify again."
}

service() {
  require_env
  render 03-rayservice-gemma4-12b.yaml | kubectl apply -f -
  info "Applied. Watch: kubectl get rayservice $SERVICE_NAME -n $NAMESPACE -w"
}

measure() {
  require_env
  MODEL_ID="$MODEL_ID" MODEL_DIR="$MODEL_DIR" RAY_LLM_TAG="$RAY_LLM_TAG" \
    exec "$(dirname "$0")/measure-deployment.sh"
}

test_endpoint() {
  info "Port-forwarding svc/${SERVICE_NAME}-serve-svc:8000 (background)..."
  kubectl port-forward "svc/${SERVICE_NAME}-serve-svc" 8000:8000 -n "$NAMESPACE" >/dev/null 2>&1 &
  local pf_pid=$!
  sleep 8
  info "Sending sample chat completion (model=$MODEL_ID)..."
  curl -sS -m 90 --retry 2 --retry-delay 3 http://localhost:8000/v1/chat/completions \
    -H 'Content-Type: application/json' \
    -d "{\"model\":\"${MODEL_ID}\",\"messages\":[{\"role\":\"user\",\"content\":\"In one sentence, what is Amazon EKS?\"}],\"max_tokens\":128}" \
    | (python3 -m json.tool 2>/dev/null || cat)
  echo
  kill "$pf_pid" 2>/dev/null || true
}

status() {
  kubectl get rayservice,rayjob,jobs,pods -n "$NAMESPACE"
  echo
  kubectl get nodes -l karpenter.sh/nodepool=gpu -o wide 2>/dev/null || true
}

cleanup() {
  info "Deleting RayService $SERVICE_NAME (Karpenter reclaims the GPU node ~15m after)..."
  kubectl delete rayservice "$SERVICE_NAME" -n "$NAMESPACE" --ignore-not-found
  info "Kept: model weights in s3://$S3_BUCKET/models/$MODEL_DIR and ray-llm image in ECR."
}

case "${1:-help}" in
  prepare)  prepare ;;
  verify)   verify ;;
  service)  service ;;
  measure)  measure ;;
  test)     test_endpoint ;;
  status)   status ;;
  cleanup)  cleanup ;;
  *) grep '^#' "$0" | head -34; ;;
esac
