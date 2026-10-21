#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source env.sh
render ray/gemma-12b.yaml | kubectl apply -f -
