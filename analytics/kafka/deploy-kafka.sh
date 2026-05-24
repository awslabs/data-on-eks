#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE=kafka

echo "Applying Kafka cluster + KafkaNodePools (controller, broker)..."
kubectl apply -f "${SCRIPT_DIR}/kafka-cluster.yaml"

echo ""
echo "Waiting for the Kafka cluster to become Ready (3-5 minutes typical)..."
kubectl wait --for=condition=Ready kafka/cluster -n "${NAMESPACE}" --timeout=600s

echo ""
kubectl get kafka,kafkanodepool -n "${NAMESPACE}"
echo ""
kubectl get pods -n "${NAMESPACE}"
echo ""
echo "Bootstrap servers:"
kubectl get kafka cluster -n "${NAMESPACE}" -o jsonpath='{range .status.listeners[*]}  {.name}: {.bootstrapServers}{"\n"}{end}'
