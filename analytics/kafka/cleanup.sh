#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=kafka

echo "Deleting KafkaTopics, KafkaUsers, the Kafka CR, and KafkaNodePools..."
kubectl delete kafkatopic --all -n "${NAMESPACE}" --ignore-not-found
kubectl delete kafkauser --all -n "${NAMESPACE}" --ignore-not-found
kubectl delete kafka cluster -n "${NAMESPACE}" --ignore-not-found
kubectl delete kafkanodepool --all -n "${NAMESPACE}" --ignore-not-found

echo "Deleting kafka-metrics ConfigMap..."
kubectl delete configmap kafka-metrics -n "${NAMESPACE}" --ignore-not-found

echo ""
echo "Waiting up to 3 minutes for broker/controller pods to terminate..."
kubectl wait --for=delete pod -l strimzi.io/cluster=cluster -n "${NAMESPACE}" --timeout=180s || true

echo ""
echo "Deleting persistent volume claims (broker + controller data)..."
kubectl delete pvc -l strimzi.io/cluster=cluster -n "${NAMESPACE}" --ignore-not-found

echo ""
echo "Uninstalling Strimzi operator..."
kubectl delete -f "https://strimzi.io/install/latest?namespace=${NAMESPACE}" -n "${NAMESPACE}" --ignore-not-found

echo ""
echo "Deleting namespace ${NAMESPACE}..."
kubectl delete namespace "${NAMESPACE}" --ignore-not-found

echo ""
echo "Cleanup complete."
