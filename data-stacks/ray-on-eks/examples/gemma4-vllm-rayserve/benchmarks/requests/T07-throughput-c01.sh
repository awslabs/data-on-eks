#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
exec "$ROOT/run-benchmark-request.sh" "${1:?scenario required}" T07 \
  --cache-mode cold --concurrency 1 --repeats 6 --max-tokens 512 --ignore-eos
