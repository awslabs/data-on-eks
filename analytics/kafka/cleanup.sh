#!/usr/bin/env bash
set -euo pipefail

# Tears down the in-lab Kafka cluster only.
# The Strimzi operator, the kafka-gp3 StorageClass, the dedicated Kafka
# NodePool, and the kafka namespace are all managed by Terraform
# (enable_kafka_lab = true) and are removed by `terraform destroy`.
# This script does NOT touch them.

NAMESPACE=kafka

echo "Deleting KafkaRebalances, KafkaTopics, KafkaUsers, the Kafka CR, and KafkaNodePools..."
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
echo "Kafka cluster resources removed. The Strimzi operator, kafka-gp3 StorageClass,"
echo "and Karpenter NodePool remain (Terraform-managed). Run 'terraform destroy'"
echo "in analytics/terraform/spark-k8s-operator/ to tear down the whole workshop."
