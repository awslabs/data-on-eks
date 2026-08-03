#!/bin/bash
# =============================================================================
# Gemma 4 12B RayService - End-to-End Deployment Timer
# =============================================================================
# Applies the RayService fresh and reports how long it takes until the endpoint
# can actually serve, broken into phases.
#
# All timings come from timestamps Kubernetes and Ray recorded themselves -
# object creationTimestamps, pod condition lastTransitionTimes, and the Serve
# replica log - never from this script's own wall clock. That matters: a poll
# loop adds its sleep interval, and a curl check adds port-forward setup, so
# wall-clock timing systematically overstates the deployment.
#
# Requires: S3_BUCKET, AWS_REGION (and valid AWS creds / kube context). Model
# weights must already be staged in S3 (./deploy.sh prepare).
#
# Usage: ./measure-deployment.sh            (measures a fresh deploy)
#        KEEP_EXISTING=1 ./measure-deployment.sh   (don't delete first)
#
# For a TRUE cold start there must be no GPU node AND no GPU NodeClaim - see
# the warning this prints. Deleting the RayService alone leaves the node up.
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

# epoch (s) of an ISO8601 k8s timestamp, portable across GNU/BSD date.
# The -u on the BSD branch is required, not cosmetic: without it BSD date parses
# the (UTC) input as local time, so on a non-UTC machine every k8s timestamp
# comes back skewed by the UTC offset. Phases computed from two k8s timestamps
# still look right because the error cancels - only comparisons against the
# pod's own log clock go visibly wrong.
iso_to_epoch() {
  local ts="$1"; [[ -z "$ts" || "$ts" == "null" ]] && { echo ""; return; }
  date -d "$ts" +%s 2>/dev/null || date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s 2>/dev/null || echo ""
}
fmt() { # seconds -> "Xm Ys"
  local s="$1"; [[ -z "$s" ]] && { echo "n/a"; return; }
  printf "%dm %02ds" $((s/60)) $((s%60))
}
delta() { # $1 $2 -> fmt(b-a), or n/a if either missing
  [[ -n "${1:-}" && -n "${2:-}" ]] || { echo "n/a"; return; }
  fmt $(( $2 - $1 ))
}

# --- Cold vs warm classification ---------------------------------------------
# Count NodeClaims as well as Nodes. Karpenter creates the claim ~60s before the
# Node registers, so checking Nodes alone reports "cold" while an instance is
# already booting - which silently understates a cold start by about a minute.
GPU_NODES=$(kubectl get nodes -l karpenter.sh/nodepool=gpu --no-headers 2>/dev/null | wc -l | tr -d ' ')
GPU_CLAIMS=$(kubectl get nodeclaims -l karpenter.sh/nodepool=gpu --no-headers 2>/dev/null | wc -l | tr -d ' ')
if (( GPU_NODES > 0 || GPU_CLAIMS > 0 )); then
  IS_COLD=0
  warn "GPU capacity already exists (${GPU_NODES} node(s), ${GPU_CLAIMS} nodeclaim(s)) -> this is a WARM start."
  warn "For a true cold start, first run:"
  warn "    kubectl delete rayservice $SERVICE_NAME -n $NAMESPACE"
  warn "    kubectl delete nodeclaim -l karpenter.sh/nodepool=gpu"
  warn "  and wait until 'kubectl get nodeclaims' shows no gpu entries."
else
  IS_COLD=1
  info "No GPU nodes or nodeclaims present -> measuring a COLD start."
fi

if [[ "${KEEP_EXISTING:-0}" != "1" ]]; then
  info "Deleting any existing RayService for a clean run..."
  kubectl delete rayservice "$SERVICE_NAME" -n "$NAMESPACE" --ignore-not-found >/dev/null 2>&1
  kubectl wait --for=delete pod -l ray.io/cluster -n "$NAMESPACE" --timeout=180s >/dev/null 2>&1 || true
fi

# --- Apply -------------------------------------------------------------------
info "Applying RayService at $(date -u +%H:%M:%SZ)..."
render 03-rayservice-gemma4-12b.yaml | kubectl apply -f - >/dev/null
POLL_START=$(date +%s)

# --- Wait until Ready (poll only to know when to stop; not used for timing) ---
info "Waiting for RayService to become Ready (timeout ${TIMEOUT_SECONDS}s)..."
READY=""
while (( $(date +%s) - POLL_START < TIMEOUT_SECONDS )); do
  cond=$(kubectl get rayservice "$SERVICE_NAME" -n "$NAMESPACE" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
  legacy=$(kubectl get rayservice "$SERVICE_NAME" -n "$NAMESPACE" \
    -o jsonpath='{.status.serviceStatus}' 2>/dev/null || true)
  if [[ "$cond" == "True" || "$legacy" == "Running" ]]; then READY="yes"; break; fi
  sleep 5
done
[[ -n "$READY" ]] || warn "RayService not Ready within timeout; printing partial timings."

# --- Verify it serves (pass/fail only - deliberately not part of any timing) --
SERVE_OK=""
kubectl port-forward "svc/${SERVICE_NAME}-serve-svc" 8000:8000 -n "$NAMESPACE" >/dev/null 2>&1 &
PF_PID=$!; sleep 8
if curl -sS -m 60 http://localhost:8000/v1/chat/completions \
      -H 'Content-Type: application/json' \
      -d "{\"model\":\"${MODEL_ID}\",\"messages\":[{\"role\":\"user\",\"content\":\"Say hi in 3 words.\"}],\"max_tokens\":16}" \
      2>/dev/null | grep -q '"choices"'; then
  SERVE_OK="yes"
fi
kill "$PF_PID" 2>/dev/null || true

# --- Gather authoritative timestamps -----------------------------------------
WORKER=$(kubectl get pods -n "$NAMESPACE" -l ray.io/group=gpu-workers \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
NODE=$(kubectl get pod "$WORKER" -n "$NAMESPACE" -o jsonpath='{.spec.nodeName}' 2>/dev/null || true)

# Epoch of a Serve-replica log line, resolved with the *pod's* clock so its
# local timezone is handled correctly.
log_epoch() {
  local pat="$1" ts
  [[ -n "$WORKER" ]] || { echo ""; return; }
  ts=$(kubectl exec "$WORKER" -n "$NAMESPACE" -c ray-worker -- bash -c \
        "grep -rhE '$pat' /tmp/ray/session_latest/logs/serve/replica_llm-app_LLMServer*.log 2>/dev/null | head -1" 2>/dev/null \
      | sed -nE 's/.*([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}).*/\1/p')
  [[ -n "$ts" ]] || { echo ""; return; }
  kubectl exec "$WORKER" -n "$NAMESPACE" -c ray-worker -- date -d "$ts" +%s 2>/dev/null || echo ""
}

t_applied=$(iso_to_epoch "$(kubectl get rayservice "$SERVICE_NAME" -n "$NAMESPACE" -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null)")
t_rs_ready=$(iso_to_epoch "$(kubectl get rayservice "$SERVICE_NAME" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].lastTransitionTime}' 2>/dev/null)")
pod_created=$(iso_to_epoch "$(kubectl get pod "$WORKER" -n "$NAMESPACE" -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null)")
pod_scheduled=$(iso_to_epoch "$(kubectl get pod "$WORKER" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="PodScheduled")].lastTransitionTime}' 2>/dev/null)")
pod_img=$(iso_to_epoch "$(kubectl get pod "$WORKER" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="PodReadyToStartContainers")].lastTransitionTime}' 2>/dev/null)")
pod_ready=$(iso_to_epoch "$(kubectl get pod "$WORKER" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].lastTransitionTime}' 2>/dev/null)")
claim_created=$(iso_to_epoch "$(kubectl get nodeclaims -l karpenter.sh/nodepool=gpu -o jsonpath='{.items[0].metadata.creationTimestamp}' 2>/dev/null)")

rep_start=$(log_epoch "Started initializing replica")
rep_dl=$(log_epoch "download model files")
rep_engine=$(log_epoch "Started vLLM engine")
rep_done=$(log_epoch "Finished initializing replica")

# --- Report ------------------------------------------------------------------
echo ""
echo "==================================================================="
echo " Gemma 4 12B RayService - end-to-end deployment timing"
echo " $( (( IS_COLD )) && echo 'COLD start (no GPU node or nodeclaim existed)' || echo 'WARM start (GPU capacity pre-existed)')"
echo " worker pod : ${WORKER:-<none>}"
echo " gpu node   : ${NODE:-<pending>}"
echo "==================================================================="
if [[ -n "$claim_created" && -n "$t_applied" ]] && (( claim_created < t_applied )); then
  warn "NodeClaim was created $(( t_applied - claim_created ))s BEFORE the RayService was applied."
  warn "Node provisioning is therefore partly outside the measured window."
fi
printf " %-52s %s\n" "Applied -> GPU pod scheduled (node provisioned)"  "$(delta "$t_applied"    "$pod_scheduled")"
printf " %-52s %s\n" "  of which: pod created -> scheduled"             "$(delta "$pod_created"  "$pod_scheduled")"
printf " %-52s %s\n" "Pod scheduled -> image pulled"                    "$(delta "$pod_scheduled" "$pod_img")"
printf " %-52s %s\n" "Image pulled -> container Ready (init + start)"   "$(delta "$pod_img"      "$pod_ready")"
printf " %-52s %s\n" "Container Ready -> replica init started"          "$(delta "$pod_ready"    "$rep_start")"
printf " %-52s %s\n" "  weight download + vLLM engine init"             "$(delta "$rep_dl"       "$rep_engine")"
printf " %-52s %s\n" "  engine started -> replica serving"              "$(delta "$rep_engine"   "$rep_done")"
echo " -------------------------------------------------------------------"
printf " %-52s %s\n" "TOTAL: applied -> replica able to serve"          "$(delta "$t_applied"    "$rep_done")"
printf " %-52s %s\n" "  (RayService Ready condition, for reference)"    "$(delta "$t_applied"    "$t_rs_ready")"
echo "==================================================================="
echo " Serve check: $( [[ -n "$SERVE_OK" ]] && echo 'PASS (endpoint returned choices)' || echo 'FAILED / not ready' )"
echo ""
echo " vLLM self-reported phase durations (from the engine log):"
if [[ -n "$WORKER" ]]; then
  kubectl exec "$WORKER" -n "$NAMESPACE" -c ray-worker -- bash -c \
    'grep -rhE "Model loading took|torch.compile took|Graph capturing finished|init engine .*took|GPU KV cache size" /tmp/ray/session_latest/logs/*.out 2>/dev/null | sed "s/^(EngineCore[^]]*]//" | sort -u' \
    2>/dev/null | tail -n 10 | sed 's/^/   /' || true
fi
echo "==================================================================="
