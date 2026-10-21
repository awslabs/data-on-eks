#!/bin/bash
# Apply the agentgateway config for the demo, in a safe order:
# Parameters (ClusterIP Service) before the Gateway, then routes and policies.
set -euo pipefail
cd "$(dirname "$0")"
source ../env.sh
./make-team-keys.sh
kubectl apply -f 00-model-catalog.yaml -f 01-parameters.yaml
kubectl apply -f 02-gateway.yaml
kubectl -n "$GW_NS" wait --for=condition=Programmed gateway/agw-demo-gw --timeout=180s
svc_type=$(kubectl -n "$GW_NS" get svc agw-demo-gw -o jsonpath='{.spec.type}')
[[ "$svc_type" == "ClusterIP" ]] || { echo "ERROR: gateway Service is $svc_type, expected ClusterIP"; exit 1; }
kubectl apply -f 03-models.yaml -f 04-grpcroute.yaml
kubectl apply -f 10-policy-llm.yaml -f 11-policy-grpc.yaml -f 12-policy-telemetry.yaml
echo "--- LoadBalancer Services in the cluster (only pre-existing ingress-nginx expected):"
kubectl get svc -A | grep -i loadbalancer || true
