#!/bin/bash
# Port-forward the demo gateway to your laptop (Ctrl-C stops all).
#   http://localhost:8080  OpenAI-compatible API (chat, embeddings, models)
#   localhost:9090         gRPC embeddings.v1.EmbeddingService (plaintext)
#   http://localhost:3000  Grafana (existing kube-prometheus-stack)
# Note: a port-forward pins you to ONE gateway pod, so per-pod rate limits
# apply exactly as configured.
export KUBECONFIG="${KUBECONFIG:-$(cd "$(dirname "$0")/../../.." && pwd)/kubeconfig.yaml}"
trap 'kill 0' EXIT INT TERM
kubectl -n agentgateway-system port-forward svc/agw-demo-gw 8080:8080 9090:9090 &
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80 >/dev/null 2>&1 &
sleep 2
echo "gateway http: http://localhost:8080   gateway grpc: localhost:9090   grafana: http://localhost:3000"
wait
