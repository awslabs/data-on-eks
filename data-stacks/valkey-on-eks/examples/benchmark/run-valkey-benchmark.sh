#!/usr/bin/env bash
# run-valkey-benchmark.sh — `valkey-benchmark` driver for the Valkey-on-EKS
# data stack. Runs canonical SET / GET / mixed workloads against either the
# replication-mode default or the cluster-mode chart, prints results in a
# stable format, and writes a summary file plus a CSV row that the
# benchmarks doc page renders.
#
# Usage:
#   ./run-valkey-benchmark.sh --mode cluster
#   ./run-valkey-benchmark.sh --mode replication --requests 500000 --pipeline 32
#   ./run-valkey-benchmark.sh --mode cluster --tests set,get,incr --output /tmp/run1
#
# Run from anywhere — the script discovers the cluster via the active KUBECONFIG.
# Requires: kubectl, AWS credentials valid for the EKS cluster.

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
MODE="cluster"               # `cluster` (sharded) or `replication` (1P+NR)
REQUESTS=500000              # -n  total ops per test
CLIENTS=50                   # -c  parallel client connections
PIPELINE=16                  # -P  pipelined commands per round-trip
DATASIZE=256                 # -d  value size in bytes
THREADS=4                    # --threads in valkey-benchmark
TESTS="set,get"              # comma-separated subset of valkey-benchmark -t
KEYSPACE_LEN=1000000         # -r  randomize keys over this many slots
QUIET=1                      # -q  quiet output (one line per test)
OUTPUT_DIR=""                # default: /tmp/valkey-bench-<timestamp>
RUNNER_NAMESPACE=""          # default: same as the target Valkey ns
KEEP_RUNNER=0                # set to 1 to keep the runner pod after exit
WORKLOAD_NAME=""             # tag the run for CSV output (default: $MODE)

# ---------------------------------------------------------------------------
# Per-mode wiring (namespace, secret, headless service hostnames). Resolved
# below in a portable case-statement so the script runs on bash 3.2 (macOS
# default) without associative arrays.
# ---------------------------------------------------------------------------
NS=""
SECRET=""
KEY=""
TARGET=""

usage() {
  cat <<USAGE
Usage: $0 [options]

Modes:
  --mode cluster      Cluster-mode chart in namespace 'valkey-cluster' (default)
  --mode replication  Replication-mode chart in namespace 'valkey'

Workload knobs (passed to valkey-benchmark):
  --requests N        Total ops per test (default $REQUESTS)
  --clients N         Parallel client connections (default $CLIENTS)
  --pipeline N        Pipeline depth per connection (default $PIPELINE)
  --datasize N        Value size in bytes (default $DATASIZE)
  --threads N         valkey-benchmark threads (default $THREADS)
  --tests CSV         Subset of valkey-benchmark -t list (default '$TESTS')
                      Common: set, get, incr, lpush, rpush, lpop, rpop,
                      sadd, hset, spop, lrange_100, lrange_300, mset
  --keyspace-len N    Randomize keys over this slot range (default $KEYSPACE_LEN)
  --workload-name STR Tag for CSV output / summary file (default = mode)

Runtime:
  --output DIR        Write summary + raw output here (default /tmp/valkey-bench-<ts>)
  --runner-namespace NS   Namespace to launch the benchmark pod in (default = target ns)
  --keep-runner       Don't delete the runner pod on exit (debug)
  -h, --help          Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)              MODE="$2"; shift 2 ;;
    --requests)          REQUESTS="$2"; shift 2 ;;
    --clients)           CLIENTS="$2"; shift 2 ;;
    --pipeline)          PIPELINE="$2"; shift 2 ;;
    --datasize)          DATASIZE="$2"; shift 2 ;;
    --threads)           THREADS="$2"; shift 2 ;;
    --tests)             TESTS="$2"; shift 2 ;;
    --keyspace-len)      KEYSPACE_LEN="$2"; shift 2 ;;
    --workload-name)     WORKLOAD_NAME="$2"; shift 2 ;;
    --output)            OUTPUT_DIR="$2"; shift 2 ;;
    --runner-namespace)  RUNNER_NAMESPACE="$2"; shift 2 ;;
    --keep-runner)       KEEP_RUNNER=1; shift ;;
    -h|--help)           usage; exit 0 ;;
    *) echo "Unknown flag: $1" >&2; usage >&2; exit 64 ;;
  esac
done

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
case "$MODE" in
  cluster)
    NS="valkey-cluster"
    SECRET="valkey-cluster-auth"
    KEY="default"
    # benchmark target = first pod's stable hostname; the cluster-aware client
    # discovers the rest via CLUSTER SLOTS at startup.
    TARGET="valkey-cluster-0.valkey-cluster-headless.valkey-cluster.svc.cluster.local"
    ;;
  replication)
    NS="valkey"
    SECRET="valkey-auth"
    KEY="default"
    # Replication mode: connect via the primary (write) Service.
    TARGET="valkey.valkey.svc.cluster.local"
    ;;
  *)
    echo "ERROR: --mode must be 'cluster' or 'replication' (got: $MODE)" >&2
    exit 64
    ;;
esac

RUNNER_NS="${RUNNER_NAMESPACE:-$NS}"
WORKLOAD_NAME="${WORKLOAD_NAME:-$MODE}"
TIMESTAMP="$(date -u +%Y%m%d-%H%M%S)"   # lowercase, RFC-1123-safe (no T/Z separators)
OUTPUT_DIR="${OUTPUT_DIR:-/tmp/valkey-bench-${TIMESTAMP}}"
mkdir -p "$OUTPUT_DIR"

# shellcheck disable=SC2043  # single-tool loop kept for symmetry with future deps
for tool in kubectl; do
  command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: $tool not found in PATH" >&2; exit 127; }
done

if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "ERROR: kubectl cannot reach the cluster. Set KUBECONFIG or run:" >&2
  echo "  aws eks update-kubeconfig --name <cluster-name> --region <region>" >&2
  exit 1
fi

if ! kubectl -n "$NS" get secret "$SECRET" >/dev/null 2>&1; then
  echo "ERROR: secret $SECRET not found in namespace $NS" >&2
  echo "       Did the chart finish installing?" >&2
  exit 1
fi

CLUSTER_FLAG=""
if [[ "$MODE" == "cluster" ]]; then
  CLUSTER_FLAG="--cluster"
fi

# ---------------------------------------------------------------------------
# Pre-run cluster snapshot
# ---------------------------------------------------------------------------
PASS="$(kubectl -n "$NS" get secret "$SECRET" -o jsonpath="{.data.$KEY}" | base64 -d)"

cat <<BANNER

==============================================================================
 Valkey on EKS — benchmark run ($WORKLOAD_NAME)
------------------------------------------------------------------------------
 Mode             : $MODE
 Target           : $TARGET:6379
 Requests / test  : $REQUESTS
 Clients          : $CLIENTS
 Pipeline depth   : $PIPELINE
 Value size       : ${DATASIZE} bytes
 Threads          : $THREADS
 Keyspace size    : $KEYSPACE_LEN
 Tests            : $TESTS
 Output dir       : $OUTPUT_DIR
==============================================================================

BANNER

echo "[pre-run] cluster_state:"
if [[ "$MODE" == "cluster" ]]; then
  kubectl -n "$NS" exec valkey-cluster-0 -c valkey -- \
    valkey-cli -a "$PASS" --no-auth-warning cluster info 2>/dev/null \
    | grep -E '^(cluster_state|cluster_slots_(assigned|ok)|cluster_known_nodes|cluster_size):' \
    || echo "  (cluster_info unavailable)"
else
  echo "  (replication mode — skipping cluster_info)"
  kubectl -n "$NS" get pods -l app.kubernetes.io/name=valkey -o wide 2>/dev/null | head -10
fi

# ---------------------------------------------------------------------------
# Launch a one-shot runner pod with the same Valkey image (so valkey-benchmark
# is on PATH and the cluster client matches the server version exactly).
# We avoid `kubectl exec` into a Valkey pod itself because the benchmark runs
# 50 concurrent connections at high QPS — keeping it off the data-plane pod
# avoids skewing the latency numbers.
# ---------------------------------------------------------------------------
RUNNER_POD="valkey-bench-${TIMESTAMP}"

cleanup() {
  if [[ "$KEEP_RUNNER" -eq 0 ]]; then
    kubectl -n "$RUNNER_NS" delete pod "$RUNNER_POD" --ignore-not-found --grace-period=2 >/dev/null 2>&1 || true
  else
    echo "[runner] keeping pod $RUNNER_NS/$RUNNER_POD (--keep-runner)"
  fi
}
trap cleanup EXIT

echo "[runner] launching $RUNNER_NS/$RUNNER_POD"

# Use the same image as the target so feature parity is guaranteed.
TARGET_IMAGE="$(kubectl -n "$NS" get pod -l app.kubernetes.io/name="valkey-cluster" \
  -o jsonpath='{.items[0].spec.containers[?(@.name=="valkey")].image}' 2>/dev/null || true)"
if [[ -z "$TARGET_IMAGE" ]]; then
  TARGET_IMAGE="$(kubectl -n "$NS" get pod -l app.kubernetes.io/name="valkey" \
    -o jsonpath='{.items[0].spec.containers[?(@.name=="valkey")].image}' 2>/dev/null || true)"
fi
TARGET_IMAGE="${TARGET_IMAGE:-docker.io/valkey/valkey:9.0.2}"

kubectl -n "$RUNNER_NS" run "$RUNNER_POD" \
  --image="$TARGET_IMAGE" \
  --restart=Never \
  --overrides="$(cat <<JSON
{
  "spec": {
    "containers": [{
      "name": "$RUNNER_POD",
      "image": "$TARGET_IMAGE",
      "command": ["sleep", "3600"],
      "resources": {
        "requests": { "cpu": "1000m", "memory": "1Gi" },
        "limits":   { "cpu": "2000m", "memory": "2Gi" }
      },
      "env": [{ "name": "VALKEY_PASSWORD", "value": "$PASS" }]
    }],
    "tolerations": [
      { "key": "workload", "operator": "Equal", "value": "valkey", "effect": "NoSchedule" }
    ]
  }
}
JSON
  )" >/dev/null

echo "[runner] waiting for pod ready..."
kubectl -n "$RUNNER_NS" wait --for=condition=Ready pod "$RUNNER_POD" --timeout=120s >/dev/null

# ---------------------------------------------------------------------------
# Run the benchmark
# ---------------------------------------------------------------------------
RAW_FILE="$OUTPUT_DIR/raw.txt"
SUMMARY_FILE="$OUTPUT_DIR/summary.txt"
CSV_FILE="$OUTPUT_DIR/results.csv"

echo "[bench] running valkey-benchmark..."
echo

QUIET_FLAG=""
if [[ "$QUIET" == "1" ]]; then
  QUIET_FLAG="-q"
fi

set +e
# shellcheck disable=SC2086  # CLUSTER_FLAG / QUIET_FLAG must word-split when empty
kubectl -n "$RUNNER_NS" exec "$RUNNER_POD" -- valkey-benchmark \
  $CLUSTER_FLAG \
  -h "$TARGET" \
  -p 6379 \
  -a "$PASS" \
  -t "$TESTS" \
  -n "$REQUESTS" \
  -c "$CLIENTS" \
  -P "$PIPELINE" \
  -d "$DATASIZE" \
  --threads "$THREADS" \
  -r "$KEYSPACE_LEN" \
  $QUIET_FLAG \
  2>&1 | tee "$RAW_FILE"
RC=${PIPESTATUS[0]}
set -e

if [[ "$RC" -ne 0 ]]; then
  echo "[bench] valkey-benchmark exited $RC" >&2
  exit "$RC"
fi

# ---------------------------------------------------------------------------
# Parse + print summary
# ---------------------------------------------------------------------------
echo
echo "[bench] parsing results..."

# `valkey-benchmark -q` prints one line per test:
#   SET: 489023.00 requests per second, p50=0.887 msec
# Capture op, RPS, p50.
{
  echo "workload=$WORKLOAD_NAME mode=$MODE timestamp=$TIMESTAMP"
  echo "requests=$REQUESTS clients=$CLIENTS pipeline=$PIPELINE datasize=$DATASIZE threads=$THREADS"
  echo "tests=$TESTS"
  echo
  printf "%-12s %15s %12s\n" "Test" "Requests/s" "p50 (ms)"
  printf "%-12s %15s %12s\n" "----" "----------" "--------"
  awk -v RS='\n' '
    /requests per second/ {
      # valkey-benchmark uses \r to overwrite progress; final result lives
      # after the last \r on the line. Strip everything up to that.
      line = $0;
      sub(/.*\r/, "", line);
      n = split(line, f, " ");
      # Expected: "SET: 800000.00 requests per second, p50=0.503 msec"
      test = f[1]; gsub(/:/, "", test);
      rps = f[2] + 0;
      p50 = line;
      sub(/.*p50=/, "", p50);
      sub(/[^0-9.].*/, "", p50);
      printf "%-12s %15.0f %12.3f\n", test, rps, p50 + 0;
    }
  ' "$RAW_FILE"
} | tee "$SUMMARY_FILE"

# CSV row: workload,mode,test,rps,p50_ms,clients,pipeline,datasize,timestamp
{
  echo "workload,mode,test,rps,p50_ms,clients,pipeline,datasize,timestamp"
  awk -v RS='\n' \
      -v wl="$WORKLOAD_NAME" -v mode="$MODE" \
      -v c="$CLIENTS" -v pl="$PIPELINE" -v ds="$DATASIZE" -v ts="$TIMESTAMP" '
    /requests per second/ {
      line = $0;
      sub(/.*\r/, "", line);
      n = split(line, f, " ");
      test = f[1]; gsub(/:/, "", test);
      rps = f[2] + 0;
      p50 = line;
      sub(/.*p50=/, "", p50);
      sub(/[^0-9.].*/, "", p50);
      printf "%s,%s,%s,%.0f,%.3f,%d,%d,%d,%s\n", wl, mode, test, rps, p50 + 0, c, pl, ds, ts;
    }
  ' "$RAW_FILE"
} > "$CSV_FILE"

# ---------------------------------------------------------------------------
# Post-run cluster check
# ---------------------------------------------------------------------------
if [[ "$MODE" == "cluster" ]]; then
  echo
  echo "[post-run] per-primary key counts:"
  for ord in 1 2 3; do
    PEER="valkey-cluster-${ord}.valkey-cluster-headless.valkey-cluster.svc.cluster.local"
    SIZE="$(kubectl -n "$RUNNER_NS" exec "$RUNNER_POD" -- \
      valkey-cli -h "$PEER" -a "$PASS" --no-auth-warning DBSIZE 2>/dev/null || echo "?")"
    printf "  valkey-cluster-%d: %s keys\n" "$ord" "$SIZE"
  done

  echo
  echo "[post-run] valkey-cli --cluster check:"
  kubectl -n "$RUNNER_NS" exec "$RUNNER_POD" -- \
    valkey-cli -a "$PASS" --no-auth-warning --cluster check "$TARGET:6379" 2>&1 \
    | sed -n '/^>>> Performing/,$p' | head -20
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
cat <<DONE

==============================================================================
 Done.

   summary : $SUMMARY_FILE
   raw     : $RAW_FILE
   csv     : $CSV_FILE

 To rerun against the other mode:
   $0 --mode $( [[ "$MODE" == "cluster" ]] && echo replication || echo cluster )

 To compare runs side by side:
   cat $OUTPUT_DIR/results.csv
==============================================================================
DONE
