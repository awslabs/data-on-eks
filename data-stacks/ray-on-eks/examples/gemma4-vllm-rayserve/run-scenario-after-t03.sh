#!/bin/bash
# Continue T04-T10 after a scenario's foreground T03 result is validated.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
SCENARIO="${1:?usage: $0 SCENARIO}"
SCENARIO=$(printf '%s' "$SCENARIO" | tr '[:lower:]' '[:upper:]')
RESULT_ROOT="$ROOT/benchmarks/results/$SCENARIO"
RUN_LOG="$RESULT_ROOT/remaining-suite.log"

mkdir -p "$RESULT_ROOT"
exec > >(tee -a "$RUN_LOG") 2>&1

echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] waiting for complete $SCENARIO T03"
while true; do
  accepted=""
  for candidate in "$RESULT_ROOT"/T03-*.json; do
    [[ -f "$candidate" ]] || continue
    if python3 - "$candidate" "$SCENARIO" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    result = json.load(f)
ok = (
    result.get("complete") is True
    and result.get("config", {}).get("scenario") == sys.argv[2]
    and result.get("config", {}).get("test_id") == "T03"
    and len(result.get("summary", [])) == 6
    and len(result.get("raw", [])) == 60
)
raise SystemExit(0 if ok else 1)
PY
    then
      accepted="$candidate"
      break
    fi
  done
  [[ -n "$accepted" ]] && break
  sleep 15
done

echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] accepted $accepted"
for test_id in T04 T05 T06 T07 T08 T09 T10; do
  case "$test_id" in
    T04) request="$ROOT/benchmarks/requests/T04-warm-latency.sh" ;;
    T05) request="$ROOT/benchmarks/requests/T05-fixed-decode.sh" ;;
    T06) request="$ROOT/benchmarks/requests/T06-prefill.sh" ;;
    T07) request="$ROOT/benchmarks/requests/T07-throughput-c01.sh" ;;
    T08) request="$ROOT/benchmarks/requests/T08-throughput-c04.sh" ;;
    T09) request="$ROOT/benchmarks/requests/T09-throughput-c08.sh" ;;
    T10) request="$ROOT/benchmarks/requests/T10-throughput-c16.sh" ;;
  esac
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] starting $SCENARIO $test_id"
  "$request" "$SCENARIO"
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] completed $SCENARIO $test_id"
done
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $SCENARIO T03-T10 suite finished"
