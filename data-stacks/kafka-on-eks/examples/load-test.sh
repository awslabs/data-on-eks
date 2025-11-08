#!/bin/bash
# Kafka Load Testing Script
# This script contains commands specifically for load testing and performance validation

case "$1" in
  create-perf-test-topic)
    kubectl exec -it kafka-cli -n kafka -- bin/kafka-topics.sh \
    --create \
    --topic test-topic-perf \
    --partitions 3 \
    --replication-factor 3 \
    --bootstrap-server data-on-eks-kafka-bootstrap:9092
    ;;
  run-producer-perf-test)
    kubectl exec -it kafka-cli -n kafka -- bin/kafka-producer-perf-test.sh \
      --topic test-topic-perf \
      --num-records 100000000 \
      --throughput -1 \
      --producer-props bootstrap.servers=data-on-eks-kafka-bootstrap:9092 \
          acks=all \
      --record-size 100 \
      --print-metrics
    ;;
  run-consumer-perf-test)
    kubectl exec -it kafka-cli -n kafka -- bin/kafka-consumer-perf-test.sh \
      --topic test-topic-perf \
      --messages 100000000 \
      --broker-list data-on-eks-kafka-bootstrap:9092 | \
      jq -R .|jq -sr 'map(./",")|transpose|map(join(": "))[]'
    ;;
  create-high-throughput-topic)
    kubectl exec -it kafka-cli -n kafka -- bin/kafka-topics.sh \
    --create \
    --topic high-throughput-test \
    --partitions 12 \
    --replication-factor 3 \
    --config min.insync.replicas=2 \
    --bootstrap-server data-on-eks-kafka-bootstrap:9092
    ;;
  run-sustained-load-test)
    echo "Starting sustained load test for 10 minutes..."
    kubectl exec -it kafka-cli -n kafka -- bin/kafka-producer-perf-test.sh \
      --topic test-topic-perf \
      --num-records 60000000 \
      --throughput 100000 \
      --producer-props bootstrap.servers=data-on-eks-kafka-bootstrap:9092 \
          acks=all \
          batch.size=16384 \
          linger.ms=5 \
      --record-size 1024 \
      --print-metrics
    ;;
  run-burst-load-test)
    echo "Starting burst load test..."
    kubectl exec -it kafka-cli -n kafka -- bin/kafka-producer-perf-test.sh \
      --topic test-topic-perf \
      --num-records 10000000 \
      --throughput -1 \
      --producer-props bootstrap.servers=data-on-eks-kafka-bootstrap:9092 \
          acks=1 \
          batch.size=32768 \
          linger.ms=0 \
      --record-size 512 \
      --print-metrics
    ;;
  cleanup-perf-topics)
    echo "Cleaning up performance test topics..."
    kubectl exec -it kafka-cli -n kafka -- bin/kafka-topics.sh \
      --delete \
      --topic test-topic-perf \
      --bootstrap-server data-on-eks-kafka-bootstrap:9092
    kubectl exec -it kafka-cli -n kafka -- bin/kafka-topics.sh \
      --delete \
      --topic high-throughput-test \
      --bootstrap-server data-on-eks-kafka-bootstrap:9092
    ;;
  list-perf-topics)
    kubectl exec -it kafka-cli -n kafka -- bin/kafka-topics.sh \
      --list \
      --bootstrap-server data-on-eks-kafka-bootstrap:9092 | grep -E "(perf|throughput)"
    ;;
  *)
    echo "Usage: $0 {create-perf-test-topic|run-producer-perf-test|run-consumer-perf-test|create-high-throughput-topic|run-sustained-load-test|run-burst-load-test|cleanup-perf-topics|list-perf-topics}"
    echo ""
    echo "Load Testing Commands:"
    echo "  create-perf-test-topic      - Create a topic optimized for performance testing"
    echo "  run-producer-perf-test      - Run producer performance test"
    echo "  run-consumer-perf-test      - Run consumer performance test"
    echo "  create-high-throughput-topic - Create topic with more partitions for high throughput"
    echo "  run-sustained-load-test     - Run sustained load test for 10 minutes"
    echo "  run-burst-load-test         - Run burst load test with maximum throughput"
    echo "  cleanup-perf-topics         - Delete all performance test topics"
    echo "  list-perf-topics            - List all performance test topics"
    exit 1
esac
