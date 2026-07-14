#!/bin/bash
# =============================================================================
# Ray Batch Inference Example - Deployment Helper
# =============================================================================
# Deploys an end-to-end batch LLM inference pipeline on the ray-on-eks stack:
#
#   01  Stage DeepSeek-R1-Distill-Llama-8B safetensors in S3 (from HuggingFace)
#   02  Mirror rayproject/ray-llm image to same-region ECR
#   03  RayService: OpenAI-compatible endpoint (vLLM + Run:ai Model Streamer)
#   04  Generator Job: 10 appends of ~200 tickets to Iceberg, 2 min apart
#   05  RayJob: batch inference by calling the RayService endpoint (pattern 1)
#   06  RayJob: batch inference with in-job vLLM engine (pattern 2)
#   07  PodMonitor: scrape Ray metrics into the stack's Prometheus
#
# Required environment variables:
#   export S3_BUCKET="<data bucket from terraform output>"
#   export AWS_REGION="us-west-2"
#
# Usage:
#   ./deploy.sh prepare     # 01 + 02: stage model, mirror image (run once)
#   ./deploy.sh service     # 03: deploy the RayService endpoint
#   ./deploy.sh generator   # 04: run the bounded ticket generator (~20 min)
#   ./deploy.sh batch-endpoint  # 05: run batch job against the endpoint
#   ./deploy.sh batch-native    # 06: run native ray.data.llm batch job
#   ./deploy.sh monitoring  # 07: scrape Ray metrics into Prometheus (once)
#   ./deploy.sh status      # show everything
#   ./deploy.sh cleanup     # delete all example resources
# =============================================================================

set -euo pipefail

NAMESPACE="raydata"
RAY_LLM_TAG="${RAY_LLM_TAG:-2.56.0-py312-cu130}"
S3_BUCKET="${S3_BUCKET:-}"
AWS_REGION="${AWS_REGION:-us-west-2}"

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
fail()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

require_env() {
  [[ -n "$S3_BUCKET" ]] || fail "export S3_BUCKET=<your data bucket> first (see: terraform output s3_bucket_id_spark_history_server)"
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
}

render() {
  sed -e "s|\$S3_BUCKET|$S3_BUCKET|g" \
      -e "s|\$AWS_REGION|$AWS_REGION|g" \
      -e "s|\$ECR_REGISTRY|$ECR_REGISTRY|g" \
      -e "s|\$RAY_LLM_TAG|$RAY_LLM_TAG|g" \
      "$1"
}

prepare() {
  require_env
  info "Creating ECR repository (idempotent)..."
  aws ecr describe-repositories --repository-names ray-llm --region "$AWS_REGION" >/dev/null 2>&1 \
    || aws ecr create-repository --repository-name ray-llm --region "$AWS_REGION" >/dev/null
  info "Refreshing ECR push token secret..."
  kubectl create secret generic ecr-push-token -n "$NAMESPACE" \
    --from-literal=token="$(aws ecr get-login-password --region "$AWS_REGION")" \
    --dry-run=client -o yaml | kubectl apply -f -
  info "Staging model weights in S3..."
  render 01-model-staging-job.yaml | kubectl apply -f -
  info "Mirroring ray-llm image to ECR..."
  render 02-image-mirror-job.yaml | kubectl apply -f -
  info "Watch with: kubectl get pods -n $NAMESPACE -w"
}

service()        { require_env; render 03-rayservice-deepseek-r1-8b.yaml | kubectl apply -f -; }
generator()      {
  require_env
  # Job specs are immutable: delete any previous run (and legacy
  # CronJob/Deployment variants of this generator) before applying.
  kubectl delete job ticket-generator -n "$NAMESPACE" --ignore-not-found
  kubectl delete deployment ticket-generator -n "$NAMESPACE" --ignore-not-found
  kubectl delete cronjob ticket-generator -n "$NAMESPACE" --ignore-not-found
  render 04-ticket-generator.yaml | kubectl apply -f -
}
batch_endpoint() {
  require_env
  kubectl delete rayjob ticket-batch-endpoint -n "$NAMESPACE" --ignore-not-found
  render 05-rayjob-batch-endpoint.yaml | kubectl apply -f -
}
batch_native() {
  require_env
  kubectl delete rayjob ticket-batch-native -n "$NAMESPACE" --ignore-not-found
  render 06-rayjob-batch-native.yaml | kubectl apply -f -
}
monitoring()     { kubectl apply -f 07-ray-metrics-podmonitor.yaml; }

status() {
  kubectl get rayservice,rayjob,jobs,deploy,pods -n "$NAMESPACE"
}

cleanup() {
  # Full cleanup lives in its own script (keeps S3/ECR one-time artifacts).
  exec "$(dirname "$0")/cleanup.sh"
}

case "${1:-help}" in
  prepare)        prepare ;;
  service)        service ;;
  generator)      generator ;;
  batch-endpoint) batch_endpoint ;;
  batch-native)   batch_native ;;
  monitoring)     monitoring ;;
  status)         status ;;
  cleanup)        cleanup ;;
  *) grep '^#' "$0" | head -30; ;;
esac
