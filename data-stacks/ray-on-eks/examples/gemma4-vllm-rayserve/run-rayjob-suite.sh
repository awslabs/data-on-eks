#!/bin/bash
# Run the T03-T10 latency/throughput suite against one scenario, one RayJob per
# test, so every test is listed in Heliostat and archived in the History Server.
#   ./run-rayjob-suite.sh DEP-G7-QAT
set -uo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
SCENARIO="${1:?scenario required}"
run() { "$ROOT/run-rayjob-benchmark.sh" "$SCENARIO" "$1" benchmark-latency.py "${@:2}"; }
run T03 --cache-mode cold --concurrency 1  --repeats 10 --max-tokens 512
run T04 --cache-mode warm --concurrency 1  --repeats 10 --max-tokens 512
run T05 --cache-mode cold --concurrency 1  --repeats 10 --max-tokens 512 --ignore-eos
run T06 --cache-mode cold --concurrency 1  --repeats 10 --max-tokens 1
run T07 --cache-mode cold --concurrency 1  --repeats 6  --max-tokens 512 --ignore-eos
run T08 --cache-mode cold --concurrency 4  --repeats 12 --max-tokens 512 --ignore-eos
run T09 --cache-mode cold --concurrency 8  --repeats 16 --max-tokens 512 --ignore-eos
run T10 --cache-mode cold --concurrency 16 --repeats 32 --max-tokens 512 --ignore-eos
