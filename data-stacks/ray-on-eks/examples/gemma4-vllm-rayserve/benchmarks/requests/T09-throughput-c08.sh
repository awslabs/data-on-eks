#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
exec "$ROOT/run-benchmark-request.sh" "${1:?scenario required}" T09 \
  --cache-mode cold --concurrency 8 --repeats 16 --max-tokens 512 --ignore-eos
