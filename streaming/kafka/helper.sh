#!/bin/bash
# set -x

# Function to get the kafka-on-eks cluster name
get_cluster_name() {
  local cluster_name=$(aws eks list-clusters --region $AWS_REGION --query "clusters[?starts_with(@, 'kafka-on-eks')]" --output text)
  if [ -z "$cluster_name" ]; then
    echo "Error: No kafka-on-eks cluster found in region $AWS_REGION" >&2
    echo "Available clusters:" >&2
    aws eks list-clusters --region $AWS_REGION --output table >&2
    return 1
  fi
  echo $cluster_name
}

case "$1" in
  update-kubeconfig)
    cluster_name=$(get_cluster_name)
    if [ $? -ne 0 ]; then
      exit 1
    fi
    echo "Found cluster: $cluster_name"
    aws eks --region $AWS_REGION update-kubeconfig --name $cluster_name
    ;;
  get-cluster-name)
    cluster_name=$(get_cluster_name)
    if [ $? -ne 0 ]; then
      exit 1
    fi
    echo "Cluster name: $cluster_name"
    ;;
  apply-kafka-cluster-manifests)
    kubectl create namespace kafka
    kubectl apply -f kafka-manifests/
    kubectl apply -f monitoring-manifests/
  ;;
  get-nodes-core)
    kubectl get nodes -l 'NodeGroupType=core'
    ;;
  get-nodes-kafka)
    kubectl get nodes -l 'NodeGroupType=kafka'
    ;;
  get-strimzi-pod-sets)
    kubectl get strimzipodsets -n kafka
    ;;
  get-kafka-pods)
    kubectl get pods -n kafka
    ;;
  create-kafka-cli-pod)
    kubectl -n kafka run --restart=Never --image=quay.io/strimzi/kafka:0.38.0-kafka-3.6.0 kafka-cli -- /bin/sh -c "exec tail -f /dev/null"
    ;;
  get-all-kafka-namespace)
    kubectl get all -n kafka
    ;;
  apply-kafka-topic)
    kubectl apply -f examples/kafka-topics.yaml
    ;;
  get-kafka-topic)
    kubectl -n kafka get KafkaTopic
    ;;
  describe-kafka-topic)
    kubectl -n kafka exec -it kafka-cli -- bin/kafka-topics.sh \
      --describe \
      --topic test-topic \
      --bootstrap-server cluster-kafka-bootstrap:9092
    ;;
  deploy-kafka-consumer)
    kubectl apply -f examples/kafka-producers-consumers.yaml
    ;;
  get-kafka-consumer-producer-steams-pods)
    kubectl -n kafka get pod -l 'app in (java-kafka-producer,java-kafka-streams,java-kafka-consumer)'
    ;;
  update-kafka-replicas)
    # Set the desired min.insync.replicas value
    NEW_MIN_ISR=4
    # Update the Kafka cluster config
    kubectl -n kafka patch kafka cluster --type='json' -p='[{"op":"replace","path":"/spec/kafka/config/min.insync.replicas","value":'$NEW_MIN_ISR'}]'
    ;;
  verify-kafka-brokers)
    kubectl -n kafka get pod -l app.kubernetes.io/name=kafka # Output should look like below
    ;;
  describe-kafka-topic-partitions)
  kubectl -n kafka exec -it kafka-cli -- bin/kafka-topics.sh \
  --describe \
  --topic my-topic \
  --bootstrap-server cluster-kafka-bootstrap:9092
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
  get-cruise-control-pods)
    kubectl -n kafka get pod -l app.kubernetes.io/name=cruise-control
    ;;
  apply-kafka-rebalance-manifest)
    kubectl apply -f kafka-manifests/kafka-rebalance.yaml
    ;;
  describe-kafka-rebalance)
    kubectl -n kafka describe KafkaRebalance my-rebalance
    ;;
  annotate-kafka-rebalance-pod)
    kubectl -n kafka annotate kafkarebalance my-rebalance strimzi.io/rebalance=approve
    ;;
  describe-kafka-partitions)
    kubectl -n kafka exec -it kafka-cli -- bin/kafka-topics.sh \
      --describe \
      --topic test-topic \
      --bootstrap-server cluster-kafka-bootstrap:9092
    ;;

  view-and-login-to-grafana-dashboard)
    echo "Grafana password is : $(aws secretsmanager get-secret-value --secret-id kafka-on-eks-grafana --region $AWS_REGION --query "SecretString" --output text)"
    kubectl port-forward svc/kube-prometheus-stack-grafana 8080:80 -n kube-prometheus-stack
    ;;
  get-grafana-login-password)
    aws secretsmanager get-secret-value --secret-id kafka-on-eks-grafana --region $AWS_REGION --query "SecretString" --output text
    ;;
  verify-consumer-topic-failover-topic)
    kubectl exec -it kafka-cli -n kafka -- bin/kafka-console-consumer.sh \
     --topic test-topic-failover \
     --bootstrap-server cluster-kafka-bootstrap:9092 \
     --partition 0 \
     --from-beginning
    ;;
  create-kafka-failover-topic)
    kubectl exec -it kafka-cli -n kafka -- bin/kafka-topics.sh \
      --create \
      --topic test-topic-failover \
      --partitions 1 \
      --replication-factor 3 \
      --bootstrap-server cluster-kafka-bootstrap:9092
    ;;
  describe-kafka-failover-topic)
    kubectl exec -it kafka-cli -n kafka -- bin/kafka-topics.sh \
      --describe \
      --topic test-topic-failover \
      --bootstrap-server cluster-kafka-bootstrap:9092
    ;;
  send-messages-to-kafka-failover-topic-from-producer)
    kubectl -n kafka run kafka-producer -ti --image=quay.io/strimzi/kafka:0.43.0-kafka-3.8.0 --rm=true --restart=Never -- bin/kafka-console-producer.sh --bootstrap-server cluster-kafka-bootstrap:9092 --topic test-topic
    ;;
  read-messages-from-kafka-failover-topic-consumer)
    kubectl -n kafka run kafka-consumer -ti --image=quay.io/strimzi/kafka:0.43.0-kafka-3.8.0 --rm=true --restart=Never -- bin/kafka-console-consumer.sh --bootstrap-server cluster-kafka-bootstrap:9092 --topic test-topic --from-beginning
    ;;
  get-kafka-cluster-pod) 
    kubectl -n kafka get pod cluster-broker-0 -o wide
  ;;
  create-node-failure)
  # Get the node where the cluster-broker-0 pod is running
  NODE=$(kubectl -n kafka get pod cluster-broker-0 -o jsonpath='{.spec.nodeName}')

  # Drain the node
  kubectl drain $NODE \
    --delete-emptydir-data \
    --force \
    --ignore-daemonsets \
    --timeout=300s

  # Get the EC2 instance ID based on the node name
  EC2_INSTANCE_ID=$(aws ec2 describe-instances \
    --filters "Name=private-dns-name,Values=$(kubectl get node $NODE -o jsonpath='{.status.addresses[?(@.type=="InternalDNS")].address}')" \
    --query 'Reservations[*].Instances[*].{Instance:InstanceId}' \
    --region $AWS_REGION --output text)
  echo "EC2 Instance ID: $EC2_INSTANCE_ID"
  # Terminate the EC2 instance
  aws ec2 terminate-instances --instance-id $EC2_INSTANCE_ID --region $AWS_REGION > /dev/null
  ;;
  validate-kafka-cluster-pod)
    kubectl -n kafka get pod cluster-broker-0 -o wide
  ;;
  *)
    echo "Kafka Helper Script - General cluster management and validation commands"
    echo "For load testing commands, use: ./load-test.sh"
    echo ""
    echo "Usage: $0 {COMMAND}"
    echo ""
    echo "Cluster Setup:"
    echo "  get-cluster-name                     - Show the current kafka-on-eks cluster name"
    echo "  update-kubeconfig                    - Update kubeconfig for kafka-on-eks cluster"
    echo "  apply-kafka-cluster-manifests        - Apply Kafka cluster and monitoring manifests"
    echo ""
    echo "Node Management:"
    echo "  get-nodes-core                       - Get core nodes"
    echo "  get-nodes-kafka                      - Get Kafka nodes"
    echo ""
    echo "Kafka Resources:"
    echo "  get-strimzi-pod-sets                 - Get Strimzi pod sets"
    echo "  get-kafka-pods                       - Get Kafka pods"
    echo "  get-all-kafka-namespace              - Get all resources in kafka namespace"
    echo "  create-kafka-cli-pod                 - Create Kafka CLI pod for testing"
    echo ""
    echo "Topic Management:"
    echo "  apply-kafka-topic                    - Apply Kafka topic manifests"
    echo "  get-kafka-topic                      - Get Kafka topics"
    echo "  describe-kafka-topic                 - Describe test topic"
    echo "  describe-kafka-topic-partitions      - Describe topic partitions"
    echo ""
    echo "Producer/Consumer:"
    echo "  deploy-kafka-consumer                - Deploy Kafka producers and consumers"
    echo "  get-kafka-consumer-producer-steams-pods - Get producer/consumer/streams pods"
    echo "  verify-kafka-producer                - Check producer logs"
    echo "  verify-kafka-streams                 - Check streams logs"
    echo "  verify-kafka-consumer                - Check consumer logs"
    echo ""
    echo "Rebalancing:"
    echo "  get-cruise-control-pods              - Get Cruise Control pods"
    echo "  apply-kafka-rebalance-manifest       - Apply rebalance manifest"
    echo "  describe-kafka-rebalance             - Describe rebalance status"
    echo "  annotate-kafka-rebalance-pod         - Approve rebalance"
    echo ""
    echo "Failover Testing:"
    echo "  create-kafka-failover-topic          - Create failover test topic"
    echo "  describe-kafka-failover-topic        - Describe failover topic"
    echo "  verify-consumer-topic-failover-topic - Verify failover topic consumer"
    echo "  send-messages-to-kafka-failover-topic-from-producer - Send messages to failover topic"
    echo "  read-messages-from-kafka-failover-topic-consumer - Read messages from failover topic"
    echo "  create-node-failure                  - Simulate node failure"
    echo "  get-kafka-cluster-pod                - Get cluster broker pod"
    echo "  validate-kafka-cluster-pod           - Validate cluster broker pod"
    echo ""
    echo "Configuration:"
    echo "  update-kafka-replicas                - Update min.insync.replicas"
    echo "  verify-kafka-brokers                 - Verify Kafka brokers"
    echo ""
    echo "Monitoring:"
    echo "  view-and-login-to-grafana-dashboard  - Access Grafana dashboard"
    echo "  get-grafana-login-password           - Get Grafana password"
    exit 1
esac
