#!/bin/bash
# =============================================================================
# Run one benchmark as its own RayJob against a running scenario's endpoint.
# =============================================================================
# Each run is a RayJob with a small CPU-only Ray cluster whose driver calls the
# scenario's Serve endpoint. Because it is a RayJob it shows up in Heliostat
# and, once its cluster is deleted, in the Ray History Server (the KubeRay
# History Server collector is added to new RayClusters by default).
#
# Usage:
#   ./run-rayjob-benchmark.sh SCENARIO TEST_ID SCRIPT [script args]
# Examples:
#   ./run-rayjob-benchmark.sh DEP-G7-QAT T03 benchmark-latency.py --cache-mode cold --repeats 10 --max-tokens 512
#   ./run-rayjob-benchmark.sh DEP-G7-QAT-KV KV kv-tier-benchmark.py --docs 150 --doc-tokens 8000 --concurrency 8
#   ./run-rayjob-benchmark.sh EMB-G7 EMB embedding-benchmark.py --requests 200
#
# The JSON artifact is written to benchmarks/results/<SCENARIO>/<TEST>-<UTC>.json.
# =============================================================================
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
NAMESPACE="${NAMESPACE:-raydata}"
RAY_IMAGE="${RAY_IMAGE:-rayproject/ray:2.56.0-py312}"
SCENARIO_ID=$(printf '%s' "${1:?scenario required}" | tr '[:lower:]' '[:upper:]')
TEST_ID="${2:?test id required}"
SCRIPT="${3:?script required}"
shift 3

CFG="$ROOT/scenarios/$(printf '%s' "$SCENARIO_ID" | tr '[:upper:]' '[:lower:]').json"
[[ -f "$CFG" ]] || { echo "unknown scenario $SCENARIO_ID" >&2; exit 1; }
cfg() { python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$CFG" "$1"; }
SERVICE_NAME=$(cfg service_name)
MODEL_ID=$(cfg model_id)

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
# RayJob names become RayCluster/Service names: keep them short and DNS-safe.
JOB=$(printf 'bench-%s-%s-%s' "$SERVICE_NAME" "$TEST_ID" "$(date -u +%H%M%S)" | tr '[:upper:]_' '[:lower:]-' | cut -c1-48 | sed 's/-$//')
OUT_DIR="$ROOT/benchmarks/results/$SCENARIO_ID"
mkdir -p "$OUT_DIR"

# Scripts and prompts are mounted into the head pod, where the job driver runs.
kubectl create configmap "$JOB-code" -n "$NAMESPACE" \
  --from-file="$ROOT/benchmark-latency.py" --from-file="$ROOT/kv-tier-benchmark.py" \
  --from-file="$ROOT/embedding-benchmark.py" --from-file="$ROOT/ray_job_wrapper.py" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl create configmap "$JOB-prompts" -n "$NAMESPACE" \
  --from-file="$ROOT/prompts" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

# Results are printed between markers (gzip+base64) and read back from the
# submitter pod logs, so the job needs no S3 credentials.
ARGS=$(printf '%q ' "$@")
# ray_job_wrapper.py runs the script as a Ray task so Ray records the job, the
# task and its logs (visible in the Ray Dashboard and History Server)
ENTRY="python -u /home/ray/bench/ray_job_wrapper.py /home/ray/bench/$SCRIPT --base-url http://${SERVICE_NAME}-serve-svc.${NAMESPACE}:8000 --model $MODEL_ID --scenario $SCENARIO_ID --out-json /tmp/out.json"
[[ "$SCRIPT" == "benchmark-latency.py" ]] && ENTRY="$ENTRY --test-id $TEST_ID --prompt-dir /home/ray/prompts"
ENTRY="$ENTRY $ARGS && echo BENCH_JSON_BEGIN && python -c \"import gzip,base64;print(base64.b64encode(gzip.compress(open('/tmp/out.json','rb').read())).decode())\" && echo BENCH_JSON_END"

kubectl apply -f - >/dev/null <<EOF
apiVersion: ray.io/v1
kind: RayJob
metadata:
  name: $JOB
  namespace: $NAMESPACE
  labels:
    benchmark.data-on-eks/scenario: $(printf '%s' "$SCENARIO_ID" | tr '[:upper:]' '[:lower:]')
    benchmark.data-on-eks/test: $(printf '%s' "$TEST_ID" | tr '[:upper:]' '[:lower:]')
spec:
  entrypoint: bash -c "$(printf '%s' "$ENTRY" | sed 's/"/\\"/g')"
  shutdownAfterJobFinishes: true
  # Leave time for the History Server collector to flush the final events
  ttlSecondsAfterFinished: 90
  activeDeadlineSeconds: 7200
  submitterPodTemplate:
    spec:
      restartPolicy: Never
      containers:
        - name: ray-job-submitter
          image: $RAY_IMAGE
          resources:
            requests: {cpu: 200m, memory: 512Mi}
  rayClusterSpec:
    rayVersion: "2.56.0"
    headGroupSpec:
      rayStartParams:
        num-cpus: "1"
      template:
        spec:
          serviceAccountName: raydata
          containers:
            - name: ray-head
              image: $RAY_IMAGE
              resources:
                requests: {cpu: "1", memory: 3Gi}
                limits: {memory: 3Gi}
              volumeMounts:
                - {name: code, mountPath: /home/ray/bench}
                - {name: prompts, mountPath: /home/ray/prompts}
          volumes:
            - {name: code, configMap: {name: $JOB-code}}
            - {name: prompts, configMap: {name: $JOB-prompts}}
EOF
echo "RayJob $JOB submitted ($SCENARIO_ID $TEST_ID $SCRIPT)"

# Wait for a terminal status
while true; do
  STATUS=$(kubectl get rayjob "$JOB" -n "$NAMESPACE" -o jsonpath='{.status.jobStatus}' 2>/dev/null || true)
  DEPLOY=$(kubectl get rayjob "$JOB" -n "$NAMESPACE" -o jsonpath='{.status.jobDeploymentStatus}' 2>/dev/null || true)
  case "$STATUS/$DEPLOY" in
    SUCCEEDED/*|FAILED/*|STOPPED/*|*/Failed) break ;;
  esac
  sleep 15
done
echo "RayJob $JOB finished: status=$STATUS"

OUT="$OUT_DIR/$TEST_ID-$STAMP.json"
kubectl logs -n "$NAMESPACE" "job/$JOB" --tail=-1 2>/dev/null \
  | sed -n '/^BENCH_JSON_BEGIN$/,/^BENCH_JSON_END$/p' | sed '1d;$d' | tr -d '\n' \
  | python3 -c 'import sys,gzip,base64;d=sys.stdin.read().strip();sys.stdout.buffer.write(gzip.decompress(base64.b64decode(d)) if d else b"")' > "$OUT"
if [[ -s "$OUT" ]]; then echo "artifact: $OUT"; else rm -f "$OUT"; echo "no artifact (status=$STATUS); see: kubectl logs -n $NAMESPACE job/$JOB" >&2; fi
kubectl delete configmap -n "$NAMESPACE" "$JOB-code" "$JOB-prompts" --ignore-not-found >/dev/null
[[ "$STATUS" == "SUCCEEDED" ]]
