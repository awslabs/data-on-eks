#!/bin/bash
# Run one named benchmark request against one already-running scenario.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
SCENARIO_ID="${1:?usage: ./run-benchmark-request.sh SCENARIO TEST_ID [benchmark args]}"
TEST_ID="${2:?usage: ./run-benchmark-request.sh SCENARIO TEST_ID [benchmark args]}"
shift 2

SCENARIO_ID=$(printf '%s' "$SCENARIO_ID" | tr '[:lower:]' '[:upper:]')
SCENARIO_FILE="$ROOT/scenarios/$(printf '%s' "$SCENARIO_ID" | tr '[:upper:]' '[:lower:]').json"
[[ -f "$SCENARIO_FILE" ]] || { echo "unknown scenario: $SCENARIO_ID" >&2; exit 1; }

read_config() {
  python3 - "$SCENARIO_FILE" "$1" <<'PY'
import json,sys
with open(sys.argv[1], encoding="utf-8") as f: print(json.load(f)[sys.argv[2]])
PY
}

SERVICE_NAME=$(read_config service_name)
MODEL_ID=$(read_config model_id)

export SERVICE_NAME MODEL_ID SCENARIO_ID TEST_ID
exec "$ROOT/run-latency-benchmark.sh" "$ROOT/prompts" \
  --scenario "$SCENARIO_ID" --test-id "$TEST_ID" "$@"
