#!/bin/bash
# Ship the embeddings app code + generated gRPC stubs as a ConfigMap, then
# apply the RayService. Re-run after editing embed_app.py; the RayService
# picks up new code when its pods restart (or delete/apply the RayService).
set -euo pipefail
cd "$(dirname "$0")/.."
source env.sh
kubectl -n "$NS" create configmap agw-demo-embed-code \
  --from-file=ray/embed_app/embed_app.py \
  --from-file=proto/gen/embeddings_pb2.py \
  --from-file=proto/gen/embeddings_pb2_grpc.py \
  --dry-run=client -o yaml | kubectl apply -f -
render ray/embeddings.yaml | kubectl apply -f -
