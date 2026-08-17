#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
exec "$ROOT/run-benchmark-request.sh" "${1:?scenario required}" T04 \
  --cache-mode warm --concurrency 1 --repeats 10 --max-tokens 512
