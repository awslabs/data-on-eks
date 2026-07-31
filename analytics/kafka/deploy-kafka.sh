#!/usr/bin/env bash
set -euo pipefail

# Preflight checks for the Kafka lab. Verifies the workshop's Terraform
# (enable_kafka_lab = true) has provisioned:
#   - Strimzi Cluster Operator running in the "kafka" namespace
#   - "kafka-gp3" StorageClass
#   - Dedicated Kafka Karpenter NodePool with workload=kafka:NoSchedule taint
#
# This script does not deploy the Kafka cluster itself — that step is
# an explicit `kubectl apply -f kafka-cluster.yaml` documented in the
# README. Splitting preflight from apply keeps the lab flow linear and
# gives the participant a clear point to inspect the manifest before
# creating cluster resources.

NAMESPACE=kafka

echo "Preflight: verifying operator, storageclass, and NodePool are in place..."
if ! kubectl -n "${NAMESPACE}" rollout status deploy/strimzi-cluster-operator --timeout=120s; then
  echo "ERROR: Strimzi operator not ready in '${NAMESPACE}'."
  echo "       Re-apply Terraform with enable_kafka_lab=true — the operator,"
  echo "       StorageClass, and NodePool all come from that single toggle."
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
echo "All prerequisites satisfied. Apply the Kafka cluster with:"
echo "  kubectl apply -f kafka-cluster.yaml"
echo "  kubectl wait --for=condition=Ready kafka/cluster -n ${NAMESPACE} --timeout=600s"
