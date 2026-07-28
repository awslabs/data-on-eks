#!/bin/bash
# =============================================================================
# Gemma 4 12B RayService - End-to-End Deployment Timer
# =============================================================================
# Applies the RayService fresh and measures wall-clock time from
# "RayService applied" until "endpoint serves an OpenAI request", then prints a
# phase breakdown reconstructed from Kubernetes event/object timestamps and the
# vLLM engine log lines. Comparable to the DeepSeek example's timing table.
#
# Requires: S3_BUCKET, AWS_REGION (and valid AWS creds / kube context). Model
# weights must already be staged in S3 (./deploy.sh prepare).
#
# Usage: ./measure-deployment.sh            (measures a fresh deploy)
#        KEEP_EXISTING=1 ./measure-deployment.sh   (don't delete first)
# =============================================================================
set -uo pipefail

NAMESPACE="raydata"
SERVICE_NAME="gemma4-12b"
MODEL_DIR="${MODEL_DIR:-gemma-4-12b-it}"
MODEL_ID="${MODEL_ID:-$MODEL_DIR}"
RAY_LLM_TAG="${RAY_LLM_TAG:-2.57.0.6c4022-py312-cu130}"
S3_BUCKET="${S3_BUCKET:-}"
AWS_REGION="${AWS_REGION:-us-west-2}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-1200}"   # 20 min ceiling

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

[[ -n "$S3_BUCKET" ]] || fail "export S3_BUCKET first."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text) \
  || fail "AWS credentials invalid/expired - refresh and retry."
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

render() {
  sed -e "s|\$S3_BUCKET|$S3_BUCKET|g" \
      -e "s|\$AWS_REGION|$AWS_REGION|g" \
      -e "s|\$ECR_REGISTRY|$ECR_REGISTRY|g" \
      -e "s|\$RAY_LLM_TAG|$RAY_LLM_TAG|g" \
      -e "s|\$MODEL_DIR|$MODEL_DIR|g" \
      -e "s|\$MODEL_ID|$MODEL_ID|g" \
      "$1"
}

# epoch (s) of an ISO8601 k8s timestamp, portable across GNU/BSD date
iso_to_epoch() {
  local ts="$1"; [[ -z "$ts" || "$ts" == "null" ]] && { echo ""; return; }
  date -d "$ts" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s 2>/dev/null || echo ""
}
fmt() { # seconds -> "Xm Ys"
  local s="$1"; [[ -z "$s" ]] && { echo "n/a"; return; }
  printf "%dm %02ds" $((s/60)) $((s%60))
}

# --- Cold vs warm classification ---------------------------------------------
EXISTING_GPU=$(kubectl get nodes -l karpenter.sh/nodepool=gpu --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "$EXISTING_GPU" -gt 0 ]]; then
  warn "$EXISTING_GPU GPU node(s) already present -> this measures a WARM start."
else
  info "No GPU nodes present -> this measures a COLD start (Karpenter provisions a node)."
fi

if [[ "${KEEP_EXISTING:-0}" != "1" ]]; then
  info "Deleting any existing RayService for a clean run..."
  kubectl delete rayservice "$SERVICE_NAME" -n "$NAMESPACE" --ignore-not-found >/dev/null 2>&1
  kubectl wait --for=delete pod -l ray.io/cluster -n "$NAMESPACE" --timeout=180s >/dev/null 2>&1 || true
fi

# --- Apply and start the clock -----------------------------------------------
T_START=$(date +%s)
info "Applying RayService at $(date -u +%H:%M:%SZ)..."
render 03-rayservice-gemma4-12b.yaml | kubectl apply -f - >/dev/null

# --- Poll until the Serve endpoint is Ready ----------------------------------
info "Waiting for RayService to become Ready (timeout ${TIMEOUT_SECONDS}s)..."
READY=""
while (( $(date +%s) - T_START < TIMEOUT_SECONDS )); do
  cond=$(kubectl get rayservice "$SERVICE_NAME" -n "$NAMESPACE" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
  legacy=$(kubectl get rayservice "$SERVICE_NAME" -n "$NAMESPACE" \
    -o jsonpath='{.status.serviceStatus}' 2>/dev/null || true)
  if [[ "$cond" == "True" || "$legacy" == "Running" ]]; then READY="yes"; break; fi
  sleep 5
done
T_READY=$(date +%s)
[[ -n "$READY" ]] || warn "RayService not Ready within timeout; printing partial timings."

# --- Verify it actually serves a request -------------------------------------
SERVE_OK=""
kubectl port-forward "svc/${SERVICE_NAME}-serve-svc" 8000:8000 -n "$NAMESPACE" >/dev/null 2>&1 &
PF_PID=$!; sleep 8
if curl -sS -m 60 http://localhost:8000/v1/chat/completions \
      -H 'Content-Type: application/json' \
      -d "{\"model\":\"${MODEL_ID}\",\"messages\":[{\"role\":\"user\",\"content\":\"Say hi in 3 words.\"}],\"max_tokens\":16}" \
      2>/dev/null | grep -q '"choices"'; then
  SERVE_OK="yes"
fi
T_SERVED=$(date +%s)
kill "$PF_PID" 2>/dev/null || true

# --- Reconstruct phase timings from object timestamps ------------------------
WORKER=$(kubectl get pods -n "$NAMESPACE" -l ray.io/group=gpu-workers \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
NODE=$(kubectl get pod "$WORKER" -n "$NAMESPACE" -o jsonpath='{.spec.nodeName}' 2>/dev/null || true)

pod_created=$(iso_to_epoch "$(kubectl get pod "$WORKER" -n "$NAMESPACE" -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null)")
pod_scheduled=$(iso_to_epoch "$(kubectl get pod "$WORKER" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="PodScheduled")].lastTransitionTime}' 2>/dev/null)")
pod_ready=$(iso_to_epoch "$(kubectl get pod "$WORKER" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].lastTransitionTime}' 2>/dev/null)")
node_created=$(iso_to_epoch "$(kubectl get node "$NODE" -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null)")

# --- Report ------------------------------------------------------------------
echo ""
echo "==================================================================="
echo " Gemma 4 12B RayService - end-to-end deployment timing"
echo " $( [[ "$EXISTING_GPU" -gt 0 ]] && echo 'WARM start (GPU node pre-existed)' || echo 'COLD start (fresh Karpenter GPU node)')"
echo " worker pod : ${WORKER:-<none>}"
echo " gpu node   : ${NODE:-<pending>}"
echo "==================================================================="
[[ -n "$pod_created" && -n "$pod_scheduled" ]] && \
  printf " %-52s %s\n" "GPU pod created -> scheduled (node provisioned)" "$(fmt $((pod_scheduled - pod_created)))"
[[ -n "$pod_scheduled" && -n "$pod_ready" ]] && \
  printf " %-52s %s\n" "Pod scheduled -> container Ready (image pull+start)" "$(fmt $((pod_ready - pod_scheduled)))"
printf " %-52s %s\n" "RayService applied -> Ready" "$(fmt $((T_READY - T_START)))"
printf " %-52s %s\n" "TOTAL: applied -> serving a request" "$(fmt $((T_SERVED - T_START)))"
echo "==================================================================="
echo " Serve check: $( [[ -n "$SERVE_OK" ]] && echo 'PASS (endpoint returned choices)' || echo 'FAILED / not ready' )"
echo ""
echo " vLLM engine phase breakdown (from Ray session logs on the worker):"
if [[ -n "$WORKER" ]]; then
  # These lines live in the Ray session logs inside the pod, not in the
  # container's stdout, so kubectl exec + grep rather than kubectl logs.
  kubectl exec "$WORKER" -n "$NAMESPACE" -- bash -c \
    'grep -rhE "Started initializing replica|download model files|Started vLLM engine|Finished initializing replica" /tmp/ray/session_latest/logs/serve/replica_llm-app_LLMServer*.log 2>/dev/null;
     grep -rhE "Model loading took|torch.compile took|Graph capturing finished|init engine .*took|GPU KV cache size" /tmp/ray/session_latest/logs/*.out 2>/dev/null | sed "s/^(EngineCore[^]]*]//" | sort -u' \
    2>/dev/null | tail -n 20 | sed 's/^/   /' || true
fi
echo "==================================================================="
