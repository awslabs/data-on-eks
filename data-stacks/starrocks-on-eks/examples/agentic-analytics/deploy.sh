#!/usr/bin/env bash
# deploy.sh — build images, push to ECR, and apply all Kubernetes manifests.
#
# Prerequisites:
#   - kubectl configured for the target cluster
#   - AWS CLI authenticated with push access to ECR
#   - Docker (or equivalent) available locally
#   - StarRocks Shared-Data cluster running in namespace "starrocks"
#   - IRSA role created with iam-policy.json and annotated on agent-sa
#
# Usage:
#   export ACCOUNT_ID=123456789012
#   export REGION=us-east-1
#   ./deploy.sh

set -euo pipefail

ACCOUNT_ID="${ACCOUNT_ID:?Set ACCOUNT_ID env var}"
REGION="${REGION:?Set REGION env var}"
ECR_BASE="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/agentic-analytics"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ──────────────────────────────────────────────────────────────────────────────
# 1. ECR login + repo creation (idempotent)
# ──────────────────────────────────────────────────────────────────────────────
echo "==> Authenticating with ECR ..."
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

for repo in agent mcp-server seed; do
  aws ecr describe-repositories --repository-names "agentic-analytics/$repo" \
    --region "$REGION" > /dev/null 2>&1 \
    || aws ecr create-repository --repository-name "agentic-analytics/$repo" \
         --region "$REGION" > /dev/null
done

# ──────────────────────────────────────────────────────────────────────────────
# 2. Build + push images
# ──────────────────────────────────────────────────────────────────────────────
echo "==> Building images ..."
docker build -t "${ECR_BASE}/agent:latest"      "$SCRIPT_DIR/agent"
docker build -t "${ECR_BASE}/mcp-server:latest" "$SCRIPT_DIR/mcp-server"
docker build -t "${ECR_BASE}/seed:latest"       "$SCRIPT_DIR/seed-job"

echo "==> Pushing images ..."
docker push "${ECR_BASE}/agent:latest"
docker push "${ECR_BASE}/mcp-server:latest"
docker push "${ECR_BASE}/seed:latest"

# ──────────────────────────────────────────────────────────────────────────────
# 3. Patch image references in manifests + apply
# ──────────────────────────────────────────────────────────────────────────────
patch_and_apply() {
  local file="$1"
  sed \
    -e "s|<ACCOUNT_ID>|${ACCOUNT_ID}|g" \
    -e "s|<REGION>|${REGION}|g" \
    "$file" | kubectl apply -f -
}

echo "==> Applying Kubernetes manifests ..."
kubectl apply -f "$SCRIPT_DIR/namespace.yaml"
kubectl apply -f "$SCRIPT_DIR/serviceaccounts.yaml"
kubectl apply -f "$SCRIPT_DIR/secret.yaml"

patch_and_apply "$SCRIPT_DIR/mcp-server/deployment.yaml"
kubectl apply -f "$SCRIPT_DIR/mcp-server/service.yaml"

patch_and_apply "$SCRIPT_DIR/agent/deployment.yaml"
kubectl apply -f "$SCRIPT_DIR/agent/service.yaml"

# ──────────────────────────────────────────────────────────────────────────────
# 4. Apply StarRocks schema (requires mysql client in PATH)
# ──────────────────────────────────────────────────────────────────────────────
if command -v mysql &> /dev/null; then
  echo "==> Waiting for StarRocks FE service ..."
  SR_HOST=$(kubectl get svc starrocks-shared-data-fe-service -n starrocks \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)

  if [[ -n "$SR_HOST" ]]; then
    echo "==> Applying StarRocks schema via $SR_HOST ..."
    mysql -h "$SR_HOST" -P 9030 -u root < "$SCRIPT_DIR/starrocks-schema.sql"
  else
    echo "WARN: StarRocks NLB not found — apply starrocks-schema.sql manually."
  fi
else
  echo "WARN: mysql not in PATH — apply starrocks-schema.sql manually against the FE NLB."
fi

# ──────────────────────────────────────────────────────────────────────────────
# 5. Wait for deployments, then run seed job
# ──────────────────────────────────────────────────────────────────────────────
echo "==> Waiting for deployments to be ready ..."
kubectl rollout status deployment/mcp-server -n agentic-analytics --timeout=120s
kubectl rollout status deployment/agent      -n agentic-analytics --timeout=120s

echo "==> Running seed job ..."
patch_and_apply "$SCRIPT_DIR/seed-job/seed-job.yaml"
kubectl wait --for=condition=complete job/seed-data \
  -n agentic-analytics --timeout=300s

echo ""
echo "==> All done.  Test with:"
echo ""
echo "  kubectl port-forward svc/agent 8080:8080 -n agentic-analytics &"
echo '  curl -s -X POST http://localhost:8080/investigate \'
echo '    -H "Content-Type: application/json" \'
echo '    -d '"'"'{"question":"CTR dropped for advertiser_42 in last 15min — what is the root cause?","advertiser_id":42}'"'"' | jq .'
echo ""
