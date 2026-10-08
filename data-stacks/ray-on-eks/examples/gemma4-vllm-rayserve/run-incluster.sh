#!/bin/bash
# Run a stdlib benchmark script on the scenario's Ray head pod (in-cluster, so no
# port-forward jitter) and copy its JSON artifact to benchmarks/results/<SCENARIO>/.
#   ./run-incluster.sh SCENARIO kv-tier-benchmark.py [script args]
#   ./run-incluster.sh SCENARIO embedding-benchmark.py [script args]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
NAMESPACE="${NAMESPACE:-raydata}"
SCENARIO_ID=$(printf '%s' "${1:?scenario required}" | tr '[:lower:]' '[:upper:]')
SCRIPT="${2:?script required}"; shift 2
CFG="$ROOT/scenarios/$(printf '%s' "$SCENARIO_ID" | tr '[:upper:]' '[:lower:]').json"
SERVICE_NAME=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["service_name"])' "$CFG")
MODEL_ID=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["model_id"])' "$CFG")
HEAD_POD=$(kubectl get pods -n "$NAMESPACE" -l "ray.io/node-type=head,app=${SERVICE_NAME}" \
  -o jsonpath='{.items[0].metadata.name}')
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
REMOTE="/tmp/bench-$STAMP"
TEST=$(basename "$SCRIPT" .py)
kubectl exec -n "$NAMESPACE" "$HEAD_POD" -c ray-head -- mkdir -p "$REMOTE"
for f in "$SCRIPT" benchmark-latency.py; do
  kubectl cp "$ROOT/$f" "$NAMESPACE/$HEAD_POD:$REMOTE/$f" -c ray-head
done
kubectl exec -n "$NAMESPACE" "$HEAD_POD" -c ray-head -- python "$REMOTE/$SCRIPT" \
  --base-url "http://${SERVICE_NAME}-serve-svc.${NAMESPACE}:8000" --model "$MODEL_ID" --scenario "$SCENARIO_ID" \
  --out-json "$REMOTE/out.json" "$@"
mkdir -p "$ROOT/benchmarks/results/$SCENARIO_ID"
OUT="$ROOT/benchmarks/results/$SCENARIO_ID/$TEST-$STAMP.json"
kubectl cp "$NAMESPACE/$HEAD_POD:$REMOTE/out.json" "$OUT" -c ray-head
echo "artifact: $OUT"
