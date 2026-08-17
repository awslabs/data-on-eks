#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
exec "$ROOT/run-benchmark-request.sh" "${1:?scenario required}" T08 \
  --cache-mode cold --concurrency 4 --repeats 12 --max-tokens 512 --ignore-eos
