#!/usr/bin/env bash
set -euo pipefail

# Deploys the Kafka cluster + KafkaNodePools onto the workshop's EKS cluster.
# Prerequisites are managed by Terraform when enable_kafka_lab = true:
#   - Strimzi Cluster Operator running in the "kafka" namespace
#   - "kafka-gp3" StorageClass
#   - Dedicated Kafka Karpenter NodePool with workload=kafka:NoSchedule taint

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE=kafka

echo "Preflight: verifying operator, storageclass, and NodePool are in place..."
if ! kubectl -n "${NAMESPACE}" rollout status deploy/strimzi-cluster-operator --timeout=120s; then
  echo "ERROR: Strimzi operator not ready in '${NAMESPACE}'."
  echo "       If the workshop's Terraform was deployed with enable_kafka_lab=false,"
  echo "       run ./install-strimzi.sh (fallback) or re-apply Terraform with the flag on."
  exit 1
fi

if ! kubectl get storageclass kafka-gp3 &>/dev/null; then
  echo "ERROR: StorageClass 'kafka-gp3' not found."
  echo "       Re-apply Terraform with enable_kafka_lab=true."
  exit 1
fi

if ! kubectl get nodepool.karpenter.sh kafka &>/dev/null; then
  echo "ERROR: Karpenter NodePool 'kafka' not found."
  echo "       Re-apply Terraform (manifests/automode/nodepool-kafka.yaml)."
  exit 1
fi

echo ""
echo "Applying Kafka cluster + KafkaNodePools (controller, broker)..."
kubectl apply -f "${SCRIPT_DIR}/kafka-cluster.yaml"

echo ""
echo "Waiting for the Kafka cluster to become Ready (3-5 minutes typical while brokers provision)..."
kubectl wait --for=condition=Ready kafka/cluster -n "${NAMESPACE}" --timeout=600s

echo ""
kubectl get kafka,kafkanodepool -n "${NAMESPACE}"
echo ""
kubectl get pods -n "${NAMESPACE}"
echo ""
echo "Bootstrap servers:"
kubectl get kafka cluster -n "${NAMESPACE}" -o jsonpath='{range .status.listeners[*]}  {.name}: {.bootstrapServers}{"\n"}{end}'
