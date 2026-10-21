#!/bin/bash
# Shared settings for agw-demo scripts. Source it: `source env.sh`
# Values are discovered from AWS/Kubernetes (no terraform commands).
AGW_DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export KUBECONFIG="${KUBECONFIG:-$AGW_DEMO_DIR/../../kubeconfig.yaml}"
export AWS_REGION="${AWS_REGION:-us-west-2}"
export NS=agw-demo
export GW_NS=agentgateway-system
export ACCOUNT_ID="${ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
export ECR_REGISTRY="$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
export RAY_LLM_IMAGE="${RAY_LLM_IMAGE:-$ECR_REGISTRY/ray-llm:2.57.0.6c4022-py312-cu130}"
# Model weights live under models/ in the stack's existing S3 bucket.
export MODELS_BUCKET="${MODELS_BUCKET:-$(aws s3api list-buckets --query "Buckets[?starts_with(Name,'ray-on-eks-spark-logs-')].Name | [0]" --output text)}"
export GEMMA_MODEL_DIR=gemma-4-12b-it-qat-w4a16-ct
export EMBED_MODEL_DIR=qwen3-embedding-0.6b
export EMBED_HF_REPO=Qwen/Qwen3-Embedding-0.6B
# ElastiCache Valkey address (rediss://host:6379) from the Terraform-created Secret.
# KubeRay's gcsFaultToleranceOptions.redisAddress is a plain string field.
export VALKEY_ADDRESS="${VALKEY_ADDRESS:-$(kubectl -n agw-demo get secret agw-demo-valkey -o jsonpath='{.data.address}' 2>/dev/null | base64 -d)}"

# Render a manifest: replaces __VAR__ placeholders with the values above.
render() {
  sed -e "s|__MODELS_BUCKET__|$MODELS_BUCKET|g" \
      -e "s|__AWS_REGION__|$AWS_REGION|g" \
      -e "s|__RAY_LLM_IMAGE__|$RAY_LLM_IMAGE|g" \
      -e "s|__GEMMA_MODEL_DIR__|$GEMMA_MODEL_DIR|g" \
      -e "s|__EMBED_MODEL_DIR__|$EMBED_MODEL_DIR|g" \
      -e "s|__EMBED_HF_REPO__|$EMBED_HF_REPO|g" \
      -e "s|__VALKEY_ADDRESS__|$VALKEY_ADDRESS|g" \
      "$1"
}
