#!/bin/bash
# =============================================================================
# Single-request latency benchmark for the Gemma 4 12B RayService
# =============================================================================
# Runs benchmark-latency.py *inside the cluster* against the Serve endpoint and
# copies the JSON results back.
#
# Why in-cluster: TTFT is a millisecond-scale measurement. Driving it from a
# laptop through `kubectl port-forward` folds your internet RTT and the
# port-forward's own jitter into every number. The client runs on the Ray head
# pod, which already has the image cached and sits on a CPU node, so it does
# not steal CPU from the vLLM engine on the GPU node.
#
# Usage:
#   ./run-latency-benchmark.sh <prompt-dir> [extra args to benchmark-latency.py]
#
# <prompt-dir> holds one prompt per file, any extension. Put your own prompts in
# benchmarks/prompt-files/ (gitignored) and run from this directory.
#
# Examples:
#   # cache-cold (every request prefills): the pessimistic bound
#   ./run-latency-benchmark.sh benchmarks/prompt-files \
#       --cache-mode cold --repeats 3 --max-tokens 512
#
#   # cache-warm (repeated identical prefix): the optimistic bound
#   ./run-latency-benchmark.sh benchmarks/prompt-files \
#       --cache-mode warm --repeats 3 --max-tokens 512
#
#   # fixed-length generation for a clean decode rate
#   ./run-latency-benchmark.sh benchmarks/prompt-files \
#       --ignore-eos --max-tokens 512
# =============================================================================
set -euo pipefail

NAMESPACE="${NAMESPACE:-raydata}"
SERVICE_NAME="${SERVICE_NAME:-gemma4-12b}"
MODEL_ID="${MODEL_ID:-gemma-4-12b-it}"
PROMPT_DIR="${1:?usage: ./run-latency-benchmark.sh <prompt-dir> [extra args]}"
shift || true

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $1"; }
fail() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

[[ -d "$PROMPT_DIR" ]] || fail "prompt dir not found: $PROMPT_DIR"

HEAD_POD=$(kubectl get pods -n "$NAMESPACE" \
  -l "ray.io/node-type=head,ray.io/serve=true" \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
[[ -n "$HEAD_POD" ]] || HEAD_POD=$(kubectl get pods -n "$NAMESPACE" \
  -o name | grep -- '-head-' | head -1 | cut -d/ -f2)
[[ -n "$HEAD_POD" ]] || fail "no Ray head pod found in $NAMESPACE"

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
REMOTE_DIR="/tmp/latbench-$STAMP"
info "Head pod: $HEAD_POD"
info "Staging prompts and script to $REMOTE_DIR ..."

kubectl exec "$HEAD_POD" -n "$NAMESPACE" -c ray-head -- \
  mkdir -p "$REMOTE_DIR/prompts"
kubectl cp "$(dirname "$0")/benchmark-latency.py" \
  "$NAMESPACE/$HEAD_POD:$REMOTE_DIR/benchmark-latency.py" -c ray-head
for f in "$PROMPT_DIR"/*; do
  [[ -f "$f" ]] || continue
  kubectl cp "$f" "$NAMESPACE/$HEAD_POD:$REMOTE_DIR/prompts/$(basename "$f")" \
    -c ray-head
done

# Server-side counters, sampled either side of the run. vLLM's metrics surface
# on the Ray metrics port (8080) prefixed ray_vllm_*. The prefill counters are
# the honest check on --cache-mode: prefill_kv_computed_tokens counts tokens
# actually prefilled, prompt_tokens counts tokens submitted. Their ratio is the
# real cache-miss rate, so a "cold" run that silently hit the prefix cache
# cannot masquerade as a valid measurement.
WORKER_POD=$(kubectl get pods -n "$NAMESPACE" -o name \
  | grep -- '-worker-' | head -1 | cut -d/ -f2 || true)

snap_metrics() {
  [[ -n "$WORKER_POD" ]] || return 0
  kubectl exec "$WORKER_POD" -n "$NAMESPACE" -c ray-worker -- python3 -c '
import urllib.request
d=urllib.request.urlopen("http://127.0.0.1:8080/metrics",timeout=10).read().decode()
want=("ray_vllm_request_prefill_kv_computed_tokens_sum",
      "ray_vllm_prompt_tokens_total","ray_vllm_generation_tokens_total",
      "ray_vllm_time_to_first_token_seconds_sum",
      "ray_vllm_time_to_first_token_seconds_count",
      "ray_vllm_e2e_request_latency_seconds_sum",
      "ray_vllm_e2e_request_latency_seconds_count")
for l in d.splitlines():
    n=l.split("{")[0]
    if n in want: print(n, l.rsplit(" ",1)[-1])
' 2>/dev/null || true
}

BEFORE=$(snap_metrics)

info "Running benchmark (model=$MODEL_ID) ..."
# -u: kubectl exec gives Python a pipe, not a tty, so without unbuffered mode
# the per-request progress lines sit in the buffer until the run ends.
kubectl exec "$HEAD_POD" -n "$NAMESPACE" -c ray-head -- \
  python3 -u "$REMOTE_DIR/benchmark-latency.py" \
    --base-url "http://${SERVICE_NAME}-serve-svc.${NAMESPACE}:8000" \
    --model "$MODEL_ID" \
    --prompt-dir "$REMOTE_DIR/prompts" \
    --out-json "$REMOTE_DIR/results.json" \
    "$@"

AFTER=$(snap_metrics)
if [[ -n "$BEFORE" && -n "$AFTER" ]]; then
  echo
  echo "----- server-side counters (delta over this run) -----"
  python3 - "$BEFORE" "$AFTER" <<'PY'
import sys
def parse(s):
    d={}
    for line in s.strip().splitlines():
        p=line.split()
        if len(p)==2:
            try: d[p[0]]=float(p[1])
            except ValueError: pass
    return d
b,a=parse(sys.argv[1]),parse(sys.argv[2])
g=lambda k: a.get(k,0)-b.get(k,0)
prompt=g("ray_vllm_prompt_tokens_total")
prefill=g("ray_vllm_request_prefill_kv_computed_tokens_sum")
gen=g("ray_vllm_generation_tokens_total")
n=g("ray_vllm_time_to_first_token_seconds_count")
ttft=g("ray_vllm_time_to_first_token_seconds_sum")
e2e=g("ray_vllm_e2e_request_latency_seconds_sum")
ne=g("ray_vllm_e2e_request_latency_seconds_count")
print(f"  requests                     {n:.0f}")
print(f"  prompt tokens submitted      {prompt:,.0f}")
print(f"  prefill KV tokens computed   {prefill:,.0f}")
# Deliberately NOT expressed as a cache-hit rate. vLLM's prefill counter uses
# its own accounting (chunked prefill, internal recompute) and routinely
# exceeds prompt_tokens_total, so any ratio against it is not a miss rate.
# Compare the two numbers ACROSS runs instead: a warm-cache run computes
# markedly fewer prefill KV tokens than a cold one for the same prompts.
print(f"  generation tokens            {gen:,.0f}")
if n>0: print(f"  server-side mean TTFT        {ttft/n*1000:.1f} ms")
if ne>0: print(f"  server-side mean E2E         {e2e/ne:.2f} s")
PY
fi

# Results always land in benchmarks/ regardless of where you invoked this from:
# that directory is gitignored, and the JSON contains your prompts' responses.
OUT_DIR="$(cd "$(dirname "$0")" && pwd)/benchmarks"
mkdir -p "$OUT_DIR"
LOCAL_OUT="$OUT_DIR/results-latency-$STAMP.json"
kubectl cp "$NAMESPACE/$HEAD_POD:$REMOTE_DIR/results.json" "$LOCAL_OUT" \
  -c ray-head 2>/dev/null && info "Results written to $LOCAL_OUT" \
  || info "(no results.json copied back)"

kubectl exec "$HEAD_POD" -n "$NAMESPACE" -c ray-head -- \
  rm -rf "$REMOTE_DIR" >/dev/null 2>&1 || true
