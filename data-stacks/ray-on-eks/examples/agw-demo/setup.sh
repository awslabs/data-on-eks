#!/bin/bash
# Build (or re-verify) the whole demo on top of the ray-on-eks stack.
# Every step is idempotent: re-running on a live demo changes nothing.
#
# Prerequisite (once, Terraform via the stack script, ~10-30 min):
#   data-stacks/ray-on-eks/terraform/data-stack.tfvars:
#     enable_agentgateway = true
#     enable_agw_demo     = true
#   cd data-stacks/ray-on-eks && ./deploy.sh
#
# Then:  ./setup.sh        (~10-15 min on cold GPU nodes)
set -euo pipefail
cd "$(dirname "$0")"
source env.sh >/dev/null
step() { echo; echo "=== $* ($(date +%H:%M:%S))"; }

step "0. Preflight: Terraform-created pieces"
kubectl get gatewayclass agentgateway >/dev/null || { echo "agentgateway not installed: set enable_agentgateway=true and run deploy.sh"; exit 1; }
kubectl get nodepool agw-demo-cpu agw-demo-gpu-gemma agw-demo-gpu-embed >/dev/null || { echo "agw-demo NodePools missing: set enable_agw_demo=true and run deploy.sh"; exit 1; }
kubectl -n "$NS" get secret/agw-demo-valkey sa/agw-ray sa/agw-model-stager >/dev/null || { echo "agw-demo namespace pieces missing: run deploy.sh"; exit 1; }
[[ -n "$VALKEY_ADDRESS" && -n "$MODELS_BUCKET" ]] || { echo "Valkey address or models bucket not found"; exit 1; }
echo "ok: GatewayClass, NodePools, Valkey secret, bucket $MODELS_BUCKET"

step "1. Stage embedding model in S3 (skips if already there)"
kubectl -n "$NS" delete job agw-demo-stage-embedding-model --ignore-not-found >/dev/null
render ray/00-stage-embedding-model.yaml | kubectl apply -f - >/dev/null
kubectl -n "$NS" wait --for=condition=complete job/agw-demo-stage-embedding-model --timeout=900s >/dev/null
echo "ok: s3://$MODELS_BUCKET/models/$EMBED_MODEL_DIR"

step "2. RayServices (Gemma 4 12B + embeddings); GPU nodes come up via Karpenter"
ray/deploy-gemma.sh
ray/deploy-embeddings.sh
kubectl -n "$NS" wait --for=condition=Ready rayservice/gemma-12b rayservice/embeddings --timeout=1500s
kubectl -n "$NS" get rayservice

step "3. agentgateway: Gateway, models, gRPC route, team keys, policies"
gateway/deploy.sh

step "4. Observability: Ray PodMonitor + Grafana dashboard"
observability/deploy.sh

step "5. Smoke test through the gateway (in-cluster)"
# Key comes from the Secret inside the pod (never on a command line).
kubectl -n "$NS" delete pod agw-demo-smoke --ignore-not-found >/dev/null
kubectl -n "$NS" apply -f - >/dev/null <<'POD'
apiVersion: v1
kind: Pod
metadata: {name: agw-demo-smoke, namespace: agw-demo, labels: {project: agw-demo}}
spec:
  restartPolicy: Never
  nodeSelector: {agw-demo/pool: cpu}
  tolerations: [{key: agw-demo, operator: Exists}]
  containers:
    - name: smoke
      image: curlimages/curl:8.11.1
      env:
        - name: KEY
          valueFrom: {secretKeyRef: {name: agw-demo-team-keys, key: TEAM_SEARCH_KEY}}
      command: ["sh", "-c"]
      args:
        - |
          GW=http://agw-demo-gw.agentgateway-system:8080
          echo "no key:  $(curl -s -o /dev/null -w %{http_code} $GW/v1/models)  (expect 401)"
          echo "models:  $(curl -s $GW/v1/models -H "Authorization: Bearer $KEY")"
          echo "chat:    $(curl -s -o /dev/null -w %{http_code} $GW/v1/chat/completions -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' -d '{"model":"gemma-12b","messages":[{"role":"user","content":"hi"}],"max_tokens":5}')  (expect 200)"
          echo "embed:   $(curl -s -o /dev/null -w %{http_code} $GW/v1/embeddings -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' -d '{"model":"qwen3-embedding-0.6b","input":"hi"}')  (expect 200)"
POD
kubectl -n "$NS" wait --for=jsonpath='{.status.phase}'=Succeeded pod/agw-demo-smoke --timeout=180s >/dev/null
kubectl -n "$NS" logs agw-demo-smoke
kubectl -n "$NS" delete pod agw-demo-smoke --wait=false >/dev/null

step "Done. Next: ./demo/port-forward.sh, then follow DEMO.md"
