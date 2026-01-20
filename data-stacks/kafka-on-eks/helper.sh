#!/bin/bash
# Kafka Helper Script for kafka-on-eks v2
# Provides utility commands for cluster management and testing

case "$1" in
  create-kafka-cli-pod)
    kubectl -n kafka run --restart=Never --image=quay.io/strimzi/kafka:0.47.0-kafka-3.9.0 kafka-cli -- /bin/sh -c "exec tail -f /dev/null"
    echo "Waiting for kafka-cli pod to be ready..."
    kubectl wait --for=condition=ready pod/kafka-cli -n kafka --timeout=60s
    ;;
  delete-kafka-cli-pod)
    kubectl -n kafka delete pod kafka-cli
    ;;
  get-kafka-pods)
    kubectl get pods -n kafka
    ;;
  get-all-kafka-namespace)
    kubectl get all -n kafka
    ;;
  get-kafka-topics)
    kubectl -n kafka get KafkaTopic
    ;;
  describe-kafka-cluster)
    kubectl describe kafka data-on-eks -n kafka
    ;;
  get-kafka-nodes)
    kubectl get nodes -l karpenter.k8s.aws/instance-family=r8g -o wide
    ;;
  get-kafka-brokers)
    kubectl -n kafka get pod -l strimzi.io/pool-name=broker
    ;;
  get-kafka-controllers)
    kubectl -n kafka get pod -l strimzi.io/pool-name=controller
    ;;
  apply-kafka-topics)
    kubectl apply -f examples/kafka-topics.yaml
    ;;
  deploy-kafka-producer-consumer)
    kubectl apply -f examples/kafka-producers-consumers.yaml
    ;;
  get-kafka-consumer-producer-streams-pods)
    kubectl -n kafka get pod -l 'app in (java-kafka-producer,java-kafka-streams,java-kafka-consumer)' --watch
    ;;
  verify-kafka-producer)
    kubectl -n kafka logs $(kubectl -n kafka get pod -l app=java-kafka-producer -o jsonpath='{.items[*].metadata.name}')
    ;;
  verify-kafka-streams)
    kubectl -n kafka logs $(kubectl -n kafka get pod -l app=java-kafka-streams -o jsonpath='{.items[*].metadata.name}')
    ;;
  verify-kafka-consumer)
    kubectl -n kafka logs $(kubectl -n kafka get pod -l app=java-kafka-consumer -o jsonpath='{.items[*].metadata.name}')
    ;;
  list-topics-via-cli)
    kubectl -n kafka exec kafka-cli -- bin/kafka-topics.sh \
      --list \
      --bootstrap-server data-on-eks-kafka-bootstrap:9092
    ;;
  describe-topic)
    TOPIC=${2:-my-topic}
    kubectl -n kafka exec kafka-cli -- bin/kafka-topics.sh \
      --describe \
      --topic $TOPIC \
      --bootstrap-server data-on-eks-kafka-bootstrap:9092
    ;;
  get-cruise-control-pods)
    kubectl -n kafka get pod -l app.kubernetes.io/name=cruise-control
    ;;
  get-strimzi-operator)
    kubectl -n strimzi-system get pods
    ;;
  get-argocd-apps)
    kubectl -n argocd get applications
    ;;
  debug-kafka-connectivity)
    echo "=== Kafka Connectivity Debug ==="
    echo "1. Checking Kafka brokers:"
    kubectl -n kafka get pod -l strimzi.io/pool-name=broker
    echo ""
    echo "2. Checking Kafka controllers:"
    kubectl -n kafka get pod -l strimzi.io/pool-name=controller
    echo ""
    echo "3. Checking Kafka service:"
    kubectl -n kafka get svc data-on-eks-kafka-bootstrap
    echo ""
    echo "4. Testing connectivity from kafka-cli pod:"
    kubectl -n kafka exec kafka-cli -- bin/kafka-broker-api-versions.sh --bootstrap-server data-on-eks-kafka-bootstrap:9092 2>/dev/null || echo "Failed to connect to Kafka brokers (ensure kafka-cli pod exists)"
    echo ""
    echo "5. Listing all topics:"
    kubectl -n kafka exec kafka-cli -- bin/kafka-topics.sh --list --bootstrap-server data-on-eks-kafka-bootstrap:9092 2>/dev/null || echo "Failed to list topics"
    ;;
  *)
    echo "Kafka Helper Script - Cluster management and validation commands"
    echo "For load testing commands, use: ./examples/load-test.sh"
    echo ""
    echo "Usage: $0 {COMMAND}"
    echo ""
    echo "Kafka CLI Pod:"
    echo "  create-kafka-cli-pod              - Create Kafka CLI pod for testing"
    echo "  delete-kafka-cli-pod              - Delete Kafka CLI pod"
    echo ""
    echo "Kafka Resources:"
    echo "  get-kafka-pods                    - Get all Kafka pods"
    echo "  get-all-kafka-namespace           - Get all resources in kafka namespace"
    echo "  get-kafka-brokers                 - Get Kafka broker pods"
    echo "  get-kafka-controllers             - Get Kafka controller pods"
    echo "  get-kafka-topics                  - Get Kafka topics (CRDs)"
    echo "  describe-kafka-cluster            - Describe Kafka cluster resource"
    echo "  get-kafka-nodes                   - Get nodes running Kafka pods (r8g instances)"
    echo ""
    echo "Topic Management:"
    echo "  apply-kafka-topics                - Apply Kafka topic manifests"
    echo "  list-topics-via-cli               - List topics using Kafka CLI"
    echo "  describe-topic [topic-name]       - Describe a specific topic (default: my-topic)"
    echo ""
    echo "Producer/Consumer:"
    echo "  deploy-kafka-producer-consumer    - Deploy Kafka producers and consumers"
    echo "  get-kafka-consumer-producer-streams-pods - Get producer/consumer/streams pods"
    echo "  verify-kafka-producer             - Check producer logs"
    echo "  verify-kafka-streams              - Check streams logs"
    echo "  verify-kafka-consumer             - Check consumer logs"
    echo ""
    echo "Rebalancing:"
    echo "  get-cruise-control-pods           - Get Cruise Control pods"
    echo ""
    echo "ArgoCD & Operators:"
    echo "  get-strimzi-operator              - Get Strimzi operator pods"
    echo "  get-argocd-apps                   - Get ArgoCD applications"
    echo ""
    echo "Debugging:"
    echo "  debug-kafka-connectivity          - Debug Kafka broker connectivity and topics"
    exit 1
esac
