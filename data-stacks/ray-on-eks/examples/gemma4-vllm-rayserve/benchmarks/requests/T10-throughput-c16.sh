#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
exec "$ROOT/run-benchmark-request.sh" "${1:?scenario required}" T10 \
  --cache-mode cold --concurrency 16 --repeats 32 --max-tokens 512 --ignore-eos
