#!/bin/bash
# =============================================================================
# Celeborn worker rolling restart — using Helm chart service DNS names
#
# This script uses Celeborn's decommission API for graceful worker restarts.
# It provides better observability and fewer transient errors compared to
# simple pod deletion.
#
# Service topology created by the official Celeborn Helm chart:
#   Master headless svc : <release>-master-svc.<namespace>.svc.cluster.local
#   Worker headless svc : <release>-worker-svc.<namespace>.svc.cluster.local
#   Per-pod stable DNS  : <release>-worker-N.<release>-worker-svc.<namespace>.svc.cluster.local
#   Master HTTP port    : 9098  (celeborn.master.http.port)
#   Worker HTTP port    : 9098  (celeborn.worker.http.port)
#
# API call routing:
#   Decommission a worker  -> POST <worker-pod>:<worker-port>/api/v1/workers/exit
#   Check cluster state    -> GET  <master-pod>:<master-port>/api/v1/workers
#   (master has authoritative view of registered/decommissioning/lost workers)
#
# Prerequisites:
#   - kubectl configured for the target cluster
#   - curl and python3 available on the script host
#   - celeborn.network.bind.preferIpAddress=false in Helm values (see NOTE below)
#
# NOTE — add this to your Helm values BEFORE running rolling restarts:
#   celeborn:
#     celeborn.network.bind.preferIpAddress: "false"
#
#   Without it, workers register using pod IP. After restart the pod IP changes.
#   The master keeps the stale IP; clients can't fetch from the restarted worker.
#   With preferIpAddress=false, workers register using their stable DNS hostname.
#   Source: https://celeborn.apache.org/docs/latest/deploy_on_k8s/
#
# Usage:
#   ./rolling-restart-celeborn.sh [options]
#   ./rolling-restart-celeborn.sh --namespace celeborn --release celeborn
#   ./rolling-restart-celeborn.sh --dry-run
# =============================================================================

set -euo pipefail

NAMESPACE="celeborn"
RELEASE="celeborn"
MASTER_HTTP_PORT="9098"
WORKER_HTTP_PORT="9096"
DRAIN_TIMEOUT=600
READY_TIMEOUT=300
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --namespace)        NAMESPACE="$2";        shift 2 ;;
    --release)          RELEASE="$2";          shift 2 ;;
    --master-http-port) MASTER_HTTP_PORT="$2"; shift 2 ;;
    --worker-http-port) WORKER_HTTP_PORT="$2"; shift 2 ;;
    --drain-timeout)    DRAIN_TIMEOUT="$2";    shift 2 ;;
    --ready-timeout)    READY_TIMEOUT="$2";    shift 2 ;;
    --dry-run)          DRY_RUN=true;          shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Names derived from Helm release — match what the chart actually creates
# Confirmed by Helm chart unit tests: service name = "<release>-worker-svc"
STATEFULSET="${RELEASE}-worker"
MASTER_SVC="${RELEASE}-master-svc"
WORKER_SVC="${RELEASE}-worker-svc"

# Stable per-pod DNS (StatefulSet + headless service)
worker_pod_dns() {
  local ordinal="$1"
  echo "${STATEFULSET}-${ordinal}.${WORKER_SVC}.${NAMESPACE}.svc.cluster.local"
}

log()  { echo "[$(date '+%H:%M:%S')] $*"; }
info() { echo "[$(date '+%H:%M:%S')] ℹ  $*"; }
ok()   { echo "[$(date '+%H:%M:%S')] ✓  $*"; }
warn() { echo "[$(date '+%H:%M:%S')] ⚠  $*"; }
fail() { echo "[$(date '+%H:%M:%S')] ✗  $*" >&2; exit 1; }

run() {
  if $DRY_RUN; then echo "  [DRY-RUN] $*"; else "$@"; fi
}

# ---------------------------------------------------------------------------
# REST API helpers via kubectl port-forward
# We port-forward to the specific pod rather than the headless service.
# The headless service load-balances across pods — we need to hit a specific
# worker pod for decommission, and a specific master pod for cluster state.
# ---------------------------------------------------------------------------

# Open a temporary port-forward, run curl, close it
_pf_get() {
  local pod="$1" pod_port="$2" path="$3"
  # Access via pod's DNS hostname instead of port-forward
  # HTTP server binds to DNS hostname, not 0.0.0.0
  local pod_dns="${pod}.${WORKER_SVC}.${NAMESPACE}.svc.cluster.local"
  if [[ "$pod" == *"master"* ]]; then
    pod_dns="${pod}.${MASTER_SVC}.${NAMESPACE}.svc.cluster.local"
  fi
  local result=""
  result=$(kubectl exec -n "$NAMESPACE" "$pod" -- curl -sf --max-time 10 "http://${pod_dns}:${pod_port}${path}" 2>/dev/null) || true
  echo "$result"
}

_pf_post() {
  local pod="$1" pod_port="$2" path="$3" body="$4"
  # Access via pod's DNS hostname instead of port-forward
  local pod_dns="${pod}.${WORKER_SVC}.${NAMESPACE}.svc.cluster.local"
  if [[ "$pod" == *"master"* ]]; then
    pod_dns="${pod}.${MASTER_SVC}.${NAMESPACE}.svc.cluster.local"
  fi
  local result=""
  result=$(kubectl exec -n "$NAMESPACE" "$pod" -- curl -sf --max-time 10 -X POST \
    -H "Content-Type: application/json" \
    -d "$body" \
    "http://${pod_dns}:${pod_port}${path}" 2>/dev/null) || true
  echo "$result"
}

# Query the MASTER for all worker states.
# Iterates master pods to find the Raft leader (only leader returns full data).
# Returns raw JSON from GET /api/v1/workers.
get_master_workers_json() {
  local master_replicas
  master_replicas=$(kubectl get statefulset "${RELEASE}-master" -n "$NAMESPACE" \
    -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "3")
  for ((m=0; m<master_replicas; m++)); do
    local mpod="${RELEASE}-master-${m}"
    local resp
    resp=$(_pf_get "$mpod" "$MASTER_HTTP_PORT" "/api/v1/workers" 2>/dev/null) || continue
    if echo "$resp" | grep -q '"workers"'; then
      echo "$resp"
      return 0
    fi
  done
  echo ""
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
log "Celeborn rolling restart"
log "  Namespace    : $NAMESPACE"
log "  Release      : $RELEASE"
log "  StatefulSet  : $STATEFULSET"
log "  Master svc   : ${MASTER_SVC}.${NAMESPACE}.svc.cluster.local"
log "  Worker svc   : ${WORKER_SVC}.${NAMESPACE}.svc.cluster.local"
log "  Drain timeout: ${DRAIN_TIMEOUT}s"
log "  Ready timeout: ${READY_TIMEOUT}s"
$DRY_RUN && warn "DRY-RUN mode — no changes will be made"
echo ""

kubectl get statefulset "$STATEFULSET" -n "$NAMESPACE" >/dev/null \
  || fail "StatefulSet $STATEFULSET not found in namespace $NAMESPACE"

REPLICAS=$(kubectl get statefulset "$STATEFULSET" -n "$NAMESPACE" \
  -o jsonpath='{.spec.replicas}')
info "Worker replicas: $REPLICAS"
[[ "$REPLICAS" -lt 2 ]] && fail "Need at least 2 replicas for safe rolling restart"

# Check if preferIpAddress is configured — warn if not
PREFER_IP=$(kubectl get configmap "${RELEASE}-conf" -n "$NAMESPACE" \
  -o jsonpath='{.data.celeborn-defaults\.conf}' 2>/dev/null | \
  grep "preferIpAddress" || echo "")
if [[ -z "$PREFER_IP" ]]; then
  warn "celeborn.network.bind.preferIpAddress not found in ConfigMap"
  warn "Workers may register with pod IP instead of DNS hostname."
  warn "After restart, master may not route to the new pod IP correctly."
  warn "Add 'celeborn.network.bind.preferIpAddress: false' to Helm values."
  echo ""
fi

# Check master API reachability
info "Checking master API reachability..."
MASTER_JSON=$(get_master_workers_json 2>/dev/null) || MASTER_JSON=""
if [[ -n "$MASTER_JSON" ]]; then
  ACTIVE=$(echo "$MASTER_JSON" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(len(d.get('workers',[])))" 2>/dev/null || echo "?")
  ok "Master API reachable — $ACTIVE active workers registered"
  MASTER_REACHABLE=true
else
  warn "Master API unreachable — registration checks will be skipped"
  MASTER_REACHABLE=false
fi
echo ""

# ---------------------------------------------------------------------------
# Rolling restart — highest ordinal first (consistent with StatefulSet RollingUpdate)
# ---------------------------------------------------------------------------
for ((i=REPLICAS-1; i>=0; i--)); do
  POD="${STATEFULSET}-${i}"
  DNS=$(worker_pod_dns "$i")
  STEP=$((REPLICAS - i))

  log "━━━ [$STEP/$REPLICAS] $POD ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  info "Stable DNS : $DNS"

  PHASE=$(kubectl get pod "$POD" -n "$NAMESPACE" \
    -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
  info "Phase      : $PHASE"

  # --- 1. Decommission: POST to THIS worker's HTTP port via port-forward ----
  DECOMM_OK=false
  if [[ "$PHASE" == "Running" ]]; then
    info "Sending decommission request..."
    if $DRY_RUN; then
      echo "  [DRY-RUN] POST http://<pf-to-${POD}>:${WORKER_HTTP_PORT}/api/v1/workers/exit"
    else
      # Decommission endpoint is on the WORKER pod directly
      # Source: https://celeborn.apache.org/docs/latest/decommissioning/
      #   "Via Celeborn Worker REST API: POST /api/v1/workers/exit"
      # NOTE: type must be uppercase enum value: DECOMMISSION, GRACEFUL, or IMMEDIATELY
      RESP=$(_pf_post "$POD" "$WORKER_HTTP_PORT" \
        "/api/v1/workers/exit" '{"type":"DECOMMISSION"}' 2>/dev/null) || RESP=""
      if [[ -n "$RESP" ]]; then
        info "Decommission accepted: $RESP"
        DECOMM_OK=true
      else
        warn "Decommission API returned empty response — proceeding with delete"
      fi
    fi
  else
    warn "Pod not Running — skipping decommission API call"
  fi

  # --- 2. Poll master until worker drains or timeout ------------------------
  if $DECOMM_OK && ! $DRY_RUN; then
    info "Polling master for drain completion (timeout: ${DRAIN_TIMEOUT}s)..."
    DRAIN_START=$(date +%s)

    while true; do
      ELAPSED=$(( $(date +%s) - DRAIN_START ))
      [[ $ELAPSED -ge $DRAIN_TIMEOUT ]] && {
        warn "Drain timeout (${ELAPSED}s) — forcing delete"
        break
      }

      # If the pod already self-terminated after drain, great
      if ! kubectl get pod "$POD" -n "$NAMESPACE" &>/dev/null; then
        ok "Pod $POD self-exited after drain (${ELAPSED}s)"
        break
      fi

      if $MASTER_REACHABLE; then
        # Query master for decommissioningWorkers list
        # Source: migration guide — GET /api/v1/workers returns decommissioningWorkers array
        WJSON=$(get_master_workers_json 2>/dev/null) || WJSON=""
        if [[ -n "$WJSON" ]]; then
          STILL_DECOMM=$(echo "$WJSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
decomm = data.get('decommissioningWorkers', [])
found = any('${POD}' in str(w) or '${DNS}' in str(w) for w in decomm)
print('yes' if found else 'no')
" 2>/dev/null || echo "unknown")

          if [[ "$STILL_DECOMM" == "no" ]]; then
            ok "Worker $POD drained — no longer in master decommissioningWorkers (${ELAPSED}s)"
            break
          fi
          info "  Still decommissioning on master... elapsed=${ELAPSED}s"
        fi
      else
        # Fallback: ask the worker pod itself
        WSTATE=$(_pf_get "$POD" "$WORKER_HTTP_PORT" "/api/v1/workers" 2>/dev/null) || WSTATE=""
        IS_D=$(echo "$WSTATE" | grep -o '"isDecommissioning":[a-z]*' | cut -d: -f2 || echo "unknown")
        [[ "$IS_D" == "false" ]] && {
          ok "Worker reports isDecommissioning=false (${ELAPSED}s)"
          break
        }
        info "  isDecommissioning=$IS_D elapsed=${ELAPSED}s"
      fi
      sleep 15
    done
  fi

  # --- 3. Delete pod -------------------------------------------------------
  info "Deleting pod $POD (StatefulSet will recreate with same PVCs)..."
  run kubectl delete pod "$POD" -n "$NAMESPACE" --wait=false
  $DRY_RUN && { echo ""; continue; }

  sleep 5  # brief pause for old pod to start terminating

  # --- 4. Wait for OLD pod to fully terminate ----------------------------
  info "Waiting for old $POD to fully terminate..."
  TERM_START=$(date +%s)
  while kubectl get pod "$POD" -n "$NAMESPACE" &>/dev/null; do
    ELAPSED=$(( $(date +%s) - TERM_START ))
    [[ $ELAPSED -ge 60 ]] && { warn "Old pod still terminating after 60s, continuing anyway"; break; }
    sleep 2
  done
  ok "Old $POD terminated"

  # --- 5. Wait for NEW pod Ready --------------------------------------------
  info "Waiting for $POD to be recreated and Ready (timeout: ${READY_TIMEOUT}s)..."
  WAIT_START=$(date +%s)
  POD_READY=false

  while true; do
    ELAPSED=$(( $(date +%s) - WAIT_START ))
    [[ $ELAPSED -ge $READY_TIMEOUT ]] && break

    PHASE=$(kubectl get pod "$POD" -n "$NAMESPACE" \
      -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending")
    READY=$(kubectl get pod "$POD" -n "$NAMESPACE" \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")

    info "  phase=$PHASE ready=$READY elapsed=${ELAPSED}s"
    [[ "$PHASE" == "Running" && "$READY" == "True" ]] && { POD_READY=true; break; }
    sleep 10
  done

  $POD_READY || fail "$POD did not become Ready within ${READY_TIMEOUT}s — aborting"
  ok "$POD is Ready"

  # --- 6. Verify re-registration on master ---------------------------------
  # Pod Ready != Celeborn registered. Must confirm master sees it as active.
  if $MASTER_REACHABLE; then
    info "Confirming $POD re-registered on Celeborn master..."
    REG_START=$(date +%s)
    REGISTERED=false
    while true; do
      ELAPSED=$(( $(date +%s) - REG_START ))
      [[ $ELAPSED -ge 90 ]] && break
      WJSON=$(get_master_workers_json 2>/dev/null) || WJSON=""
      if [[ -n "$WJSON" ]]; then
        FOUND=$(echo "$WJSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
workers = data.get('workers', [])
found = any('${POD}' in str(w) or '${DNS}' in str(w) for w in workers)
print('yes' if found else 'no')
" 2>/dev/null || echo "no")
        [[ "$FOUND" == "yes" ]] && { REGISTERED=true; break; }
      fi
      info "  Waiting for master registration... ${ELAPSED}s"
      sleep 10
    done

    if $REGISTERED; then
      ok "$POD registered on Celeborn master"
    else
      fail "$POD Ready but NOT registered on master after 90s.
Check worker logs and verify celeborn.network.bind.preferIpAddress=false is set."
    fi
  else
    warn "Skipping master registration check (master unreachable)"
    sleep 30
  fi

  # --- 7. Stability wait: ensure pod runs stably before next restart -------
  info "Waiting 120s for $POD to stabilize before next restart..."
  STABLE_START=$(date +%s)
  while true; do
    ELAPSED=$(( $(date +%s) - STABLE_START ))
    [[ $ELAPSED -ge 120 ]] && break
    
    # Verify pod is still Running during stability period
    PHASE=$(kubectl get pod "$POD" -n "$NAMESPACE" \
      -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    READY=$(kubectl get pod "$POD" -n "$NAMESPACE" \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
    
    if [[ "$PHASE" != "Running" || "$READY" != "True" ]]; then
      fail "$POD became unhealthy during stability wait (phase=$PHASE ready=$READY)"
    fi
    
    info "  Stability check: phase=$PHASE ready=$READY elapsed=${ELAPSED}s/120s"
    sleep 15
  done
  ok "$POD stable for 120s"

  echo ""
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ok "Rolling restart complete — all $REPLICAS workers restarted"
echo ""
log "Pod status:"
kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/role=worker" -o wide 2>/dev/null || \
  kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/component=worker" -o wide
echo ""
if $MASTER_REACHABLE; then
  log "Cluster worker registry (from master API):"
  get_master_workers_json | python3 -c "
import sys, json
try:
  data = json.load(sys.stdin)
  workers = data.get('workers', [])
  print(f'  Active registered workers : {len(workers)}')
  for w in workers:
    print(f'    {w.get(\"host\",\"?\")}  usedSlots={w.get(\"usedSlots\",0)}')
  for key in ('lostWorkers', 'excludedWorkers', 'decommissioningWorkers', 'shutdownWorkers'):
    val = data.get(key, [])
    if val: print(f'  {key}: {len(val)}')
except Exception as e:
  print(f'  (parse error: {e})')
" 2>/dev/null || true
fi
