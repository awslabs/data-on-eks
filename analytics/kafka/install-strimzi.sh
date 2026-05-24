#!/usr/bin/env bash
set -euo pipefail

# Install latest Strimzi Cluster Operator into the kafka namespace
# Reference: https://strimzi.io/quickstarts/

NAMESPACE=kafka

echo "Creating namespace: ${NAMESPACE}"
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "Installing latest Strimzi operator into ${NAMESPACE}..."
# 'kubectl create' is intentional: the install bundle contains CRDs that
# can fail with 'kubectl apply' due to Kubernetes annotation size limits.
kubectl create -f "https://strimzi.io/install/latest?namespace=${NAMESPACE}" -n "${NAMESPACE}"

echo ""
echo "Waiting for the Strimzi cluster operator to become Ready..."
kubectl -n "${NAMESPACE}" rollout status deploy/strimzi-cluster-operator --timeout=180s

echo ""
kubectl get pods -n "${NAMESPACE}"
echo ""
echo "Strimzi operator is ready. Next: run ./deploy-kafka.sh"
