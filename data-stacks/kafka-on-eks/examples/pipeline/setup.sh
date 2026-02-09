#!/bin/bash
set -e

echo "=================================================="
echo "  Clickstream Analytics Pipeline Setup"
echo "=================================================="
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl not found. Please install kubectl first."
    exit 1
fi

# Check if connected to cluster
if ! kubectl get ns kafka &> /dev/null; then
    echo "❌ Cannot connect to Kafka namespace. Please ensure:"
    echo "   1. EKS cluster is running"
    echo "   2. kubectl is configured correctly"
    echo "   3. Kafka namespace exists"
    exit 1
fi

echo "✓ Connected to Kubernetes cluster"
echo ""

# Step 1: Create Kafka topics
echo "📋 Step 1: Creating Kafka topics..."
kubectl apply -f kafka-topics.yaml
echo "✓ Topics created"
echo ""

# Wait for topics to be ready
echo "⏳ Waiting for topics to be ready..."
for i in {1..30}; do
    if kubectl get kafkatopic clickstream-events -n kafka &> /dev/null && \
       kubectl get kafkatopic clickstream-metrics -n kafka &> /dev/null; then
        echo "✓ Topics are ready"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "❌ Timeout waiting for topics"
        exit 1
    fi
    sleep 2
done
echo ""

# Step 2: Deploy Producer
echo "📋 Step 2: Deploying Clickstream Producer..."
kubectl apply -f deploy/producer-deployment.yaml
echo "✓ Producer deployed"
echo ""

# Step 3: Deploy Python Streams Processing Job
echo "📋 Step 3: Deploying Python Streams Processing Job..."
kubectl apply -f deploy/streams-deployment-python.yaml
echo "✓ Python streams processor deployed"
echo ""

# Step 4: Deploy Consumer
echo "📋 Step 4: Deploying Metrics Consumer..."
kubectl apply -f deploy/consumer-deployment.yaml
echo "✓ Consumer deployed"
echo ""

echo "=================================================="
echo "  ✅ Pipeline Setup Complete!"
echo "=================================================="
echo ""
echo "📊 Pipeline Architecture:"
echo "   Producer → Kafka (clickstream-events)"
echo "            → Python Streams (kstreams library, 5-min windows)"
echo "            → Kafka (clickstream-metrics)"
echo "            → Consumer"
echo ""
echo "🔍 Verify Deployments:"
echo "   kubectl get pods -n kafka | grep clickstream"
echo ""
echo "📈 View Logs:"
echo "   Producer:  kubectl logs -f deployment/clickstream-producer -n kafka"
echo "   Processor: kubectl logs -f deployment/clickstream-streams-processor -n kafka"
echo "   Consumer:  kubectl logs -f deployment/clickstream-consumer -n kafka"
echo ""
echo "🧹 Cleanup:"
echo "   ./cleanup.sh"
echo ""
