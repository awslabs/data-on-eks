#!/bin/bash
set -e

echo "=================================================="
echo "  Clickstream Analytics Pipeline Cleanup"
echo "=================================================="
echo ""

# Delete deployments
echo "🗑️  Deleting deployments..."
kubectl delete -f deploy/consumer-deployment.yaml --ignore-not-found=true
kubectl delete -f deploy/streams-deployment-python.yaml --ignore-not-found=true
kubectl delete -f deploy/producer-deployment.yaml --ignore-not-found=true
echo "✓ Deployments deleted"
echo ""

# Delete topics
echo "🗑️  Deleting Kafka topics..."
kubectl delete -f kafka-topics.yaml --ignore-not-found=true
echo "✓ Topics deleted"
echo ""

echo "=================================================="
echo "  ✅ Cleanup Complete!"
echo "=================================================="
echo ""
