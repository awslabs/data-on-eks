#!/bin/bash
# Tear down the demo in the right order. DRY RUN by default: it only lists
# what it would delete. Nothing that existed before the demo is touched
# (KubeRay, Karpenter, Prometheus/Grafana, ingress-nginx, the S3 bucket, the
# Gemma 4 weights under models/).
#
#   ./cleanup.sh                  # dry run: show what would be deleted
#   ./cleanup.sh --yes            # delete Kubernetes-side demo resources
#   ./cleanup.sh --yes --models   # also delete s3://<bucket>/models/qwen3-embedding-0.6b/
#
# Then remove the AWS/Karpenter side with Terraform via the stack script:
#   data-stack.tfvars: enable_agw_demo = false   (NodePools, NodeClasses, Valkey, IAM, namespace)
#                      enable_agentgateway = false (only if nothing else uses agentgateway)
#   cd data-stacks/ray-on-eks && ./deploy.sh
set -euo pipefail
cd "$(dirname "$0")"
source env.sh >/dev/null
YES=false; MODELS=false
for a in "$@"; do case "$a" in --yes) YES=true ;; --models) MODELS=true ;; esac; done
run() { if $YES; then echo "+ $*"; "$@" || true; else echo "would: $*"; fi; }
list() { echo "  $(kubectl "$@" --no-headers -o custom-columns=KIND:.kind,NAME:.metadata.name 2>/dev/null | tr -s ' ' | paste -sd ',' - || true)"; }

echo "== 1. Load/test pods and jobs (agw-demo)"
list -n "$NS" get jobs,pods -l 'app in (agw-demo-loadgen,agw-demo-overhead,agw-demo-model-staging,agw-demo-client)'
run kubectl -n "$NS" delete job -l 'app in (agw-demo-loadgen,agw-demo-overhead)' --ignore-not-found
run kubectl -n "$NS" delete job agw-demo-stage-embedding-model --ignore-not-found
run kubectl -n "$NS" delete pod -l app=agw-demo-client --ignore-not-found
run kubectl -n "$NS" delete pod agw-demo-smoke --ignore-not-found

echo "== 2. RayServices (releases the 4 GPU nodes and the 2 head CPU nodes)"
list -n "$NS" get rayservice
run kubectl -n "$NS" delete rayservice gemma-12b embeddings --ignore-not-found --wait=true --timeout=300s
run kubectl -n "$NS" delete service embeddings-grpc-svc --ignore-not-found
run kubectl -n "$NS" delete configmap agw-demo-embed-code agw-demo-proto agw-demo-loadgen agw-demo-imgcheck --ignore-not-found

echo "== 3. Gateway resources (agentgateway-system) — the Gateway owns the 3 proxy pods"
list -n "$GW_NS" get agentgatewaypolicy,agentgatewaymodel,grpcroute,gateway,agentgatewayparameters -l project=agw-demo
run kubectl -n "$GW_NS" delete agentgatewaypolicy agw-demo-llm agw-demo-grpc agw-demo-telemetry --ignore-not-found
run kubectl -n "$GW_NS" delete agentgatewaymodel gemma-12b qwen3-embedding-0.6b --ignore-not-found
run kubectl -n "$GW_NS" delete grpcroute embeddings-grpc --ignore-not-found
run kubectl -n "$NS" delete referencegrant allow-agw-demo-gateway-routes --ignore-not-found
run kubectl -n "$GW_NS" delete gateway agw-demo-gw --ignore-not-found --wait=true --timeout=120s
run kubectl -n "$GW_NS" delete agentgatewayparameters agw-demo-gw --ignore-not-found
run kubectl -n "$GW_NS" delete configmap agw-demo-model-costs agw-demo-api-keys --ignore-not-found
run kubectl -n "$NS" delete secret agw-demo-team-keys --ignore-not-found

echo "== 4. Observability add-ons"
run kubectl -n "$NS" delete podmonitor agw-demo-ray --ignore-not-found
run kubectl -n "$NS" delete configmap agw-demo-dashboard-tenants --ignore-not-found

if $MODELS; then
  echo "== 5. Staged embedding model in S3"
  run aws s3 rm "s3://$MODELS_BUCKET/models/$EMBED_MODEL_DIR/" --recursive
fi

if $YES; then
  echo "== Waiting for demo GPU/CPU nodes to terminate (Karpenter, empty-node consolidation up to 30m)"
  for i in $(seq 1 24); do
    n=$(kubectl get nodeclaims -l 'karpenter.sh/nodepool in (agw-demo-gpu-gemma,agw-demo-gpu-embed)' --no-headers 2>/dev/null | wc -l | tr -d ' ')
    echo "  $(date +%T) demo GPU nodeclaims left: $n"; [[ "$n" == "0" ]] && break; sleep 30
  done
  echo "  (removing the NodePools in the next step also terminates any remaining demo nodes)"
fi

echo
echo "LoadBalancer Services now (only pre-existing ingress-nginx expected):"
kubectl get svc -A | grep -i loadbalancer || true
echo
echo "Next: set enable_agw_demo = false (and enable_agentgateway = false if unused) in"
echo "      data-stacks/ray-on-eks/terraform/data-stack.tfvars, then: cd data-stacks/ray-on-eks && ./deploy.sh"
$YES || echo "(dry run: nothing was deleted; re-run with --yes)"
