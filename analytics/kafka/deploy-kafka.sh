#!/usr/bin/env bash
set -euo pipefail

# Deploys the Kafka cluster onto the Spark-on-EKS Auto Mode cluster.
# The Strimzi Cluster Operator is already installed by Terraform
# (enable_kafka = true) into the "kafka" namespace, and a dedicated
# Kafka NodePool (NodeGroupType=KafkaBroker, On-Demand) is provisioned.
# This script only applies the Kafka + KafkaNodePool custom resources.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE=kafka

echo "Verifying the Strimzi Cluster Operator is running in namespace '${NAMESPACE}'..."
if ! kubectl -n "${NAMESPACE}" rollout status deploy/strimzi-cluster-operator --timeout=120s; then
  echo "ERROR: Strimzi operator not found/ready in '${NAMESPACE}'."
  echo "Ensure the workshop was deployed with enable_kafka = true (Terraform installs the operator)."
  exit 1
fi

echo ""
echo "Applying Kafka cluster + KafkaNodePools (controller, broker)..."
kubectl apply -f "${SCRIPT_DIR}/kafka-cluster.yaml"

echo ""
echo "Waiting for the Kafka cluster to become Ready (3-5 minutes typical while nodes provision)..."
kubectl wait --for=condition=Ready kafka/cluster -n "${NAMESPACE}" --timeout=600s

echo ""
kubectl get kafka,kafkanodepool -n "${NAMESPACE}"
echo ""
kubectl get pods -n "${NAMESPACE}"
echo ""
echo "Bootstrap servers:"
kubectl get kafka cluster -n "${NAMESPACE}" -o jsonpath='{range .status.listeners[*]} {.name}: {.bootstrapServers}{"\n"}{end}'
