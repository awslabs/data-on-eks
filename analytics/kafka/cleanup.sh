#!/usr/bin/env bash
set -euo pipefail

# Tears down the in-lab Kafka cluster resources only.
# The Strimzi Cluster Operator and the Kafka NodePool are managed by
# Terraform (enable_kafka) and are removed by the workshop's cleanup.sh /
# terraform destroy - do NOT uninstall the operator here.

NAMESPACE=kafka

echo "Deleting KafkaTopics, KafkaUsers, KafkaRebalances, the Kafka CR, and KafkaNodePools..."
kubectl delete kafkarebalance --all -n "${NAMESPACE}" --ignore-not-found
kubectl delete kafkatopic --all -n "${NAMESPACE}" --ignore-not-found
kubectl delete kafkauser --all -n "${NAMESPACE}" --ignore-not-found
kubectl delete kafka cluster -n "${NAMESPACE}" --ignore-not-found
kubectl delete kafkanodepool --all -n "${NAMESPACE}" --ignore-not-found

echo ""
echo "Deleting kafka-metrics ConfigMap..."
kubectl delete configmap kafka-metrics -n "${NAMESPACE}" --ignore-not-found

echo ""
echo "Waiting up to 3 minutes for broker/controller pods to terminate..."
kubectl wait --for=delete pod -l strimzi.io/cluster=cluster -n "${NAMESPACE}" --timeout=180s || true

echo ""
echo "Deleting persistent volume claims (broker + controller data)..."
kubectl delete pvc -l strimzi.io/cluster=cluster -n "${NAMESPACE}" --ignore-not-found

echo ""
echo "Kafka cluster resources removed. The Strimzi operator and Kafka NodePool"
echo "remain (managed by Terraform); they are removed by the workshop teardown."
