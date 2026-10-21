#!/bin/bash
# Observability for the demo: Ray PodMonitor + Grafana dashboard ConfigMap.
# The Grafana sidecar (kube-prometheus-stack) loads any ConfigMap labelled
# grafana_dashboard=1 from any namespace; the agentgateway chart already
# created PodMonitor/ServiceMonitor for the gateway.
set -euo pipefail
cd "$(dirname "$0")/.."
source env.sh >/dev/null
python3 observability/build_dashboard.py
kubectl apply -f observability/podmonitor-ray.yaml
kubectl -n agw-demo create configmap agw-demo-dashboard-tenants \
  --from-file=agw-demo-tenant-chargeback.json=demo/dashboards/agw-demo-tenant-chargeback.json \
  --dry-run=client -o yaml | kubectl label --local -f - grafana_dashboard=1 project=agw-demo -o yaml | kubectl apply -f -
