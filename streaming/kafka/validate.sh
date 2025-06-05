#!/bin/bash
# set -x
case "$1" in
  update-kubeconfig)
    aws eks --region $AWS_REGION update-kubeconfig --name kafka-on-eks
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

# TODO

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
  create-kafka-perf-test-topic)
    kubectl exec -it kafka-cli -n kafka -- bin/kafka-topics.sh \
    --create \
    --topic test-topic-perf \
    --partitions 3 \
    --replication-factor 3 \
    --bootstrap-server cluster-kafka-bootstrap:9092
    ;;
  run-kafka-topic-perf-test)
    kubectl exec -it kafka-cli -n kafka -- bin/kafka-producer-perf-test.sh \
      --topic test-topic-perf \
      --num-records 100000000 \
      --throughput -1 \
      --producer-props bootstrap.servers=cluster-kafka-bootstrap:9092 \
          acks=all \
      --record-size 100 \
      --print-metrics
    ;;
  verify-kafka-consumer-perf-test-topic)
    kubectl exec -it kafka-cli -n kafka -- bin/kafka-consumer-perf-test.sh \
      --topic test-topic-perf \
      --messages 100000000 \
      --broker-list bootstrap.servers=cluster-kafka-bootstrap.kafka.svc.cluster.local:9092 | \
      jq -R .|jq -sr 'map(./",")|transpose|map(join(": "))[]'
    ;;
  view-and-login-to-grafana-dashboard)
    echo "Grafana password is : $(aws secretsmanager get-secret-value --secret-id kafka-on-eks-grafana --region $AWS_REGION --query "SecretString" --output text)"
    kubectl port-forward svc/kube-prometheus-stack-grafana 8080:80 -n kube-prometheus-stack
    ;;
  get-grafana-login-password)
    aws secretsmanager get-secret-value --secret-id kafka-on-eks-grafana --region $AWS_REGION --query "SecretString" --output text
    ;;
  create-node-failure)
    kubectl drain ip-10-1-2-35.us-west-2.compute.internal \
      --delete-emptydir-data \
      --force \
      --ignore-daemonsets
    ec2_instance_id=$(aws ec2 describe-instances \
      --filters "Name=private-dns-name,Values=ip-10-1-2-35.us-west-2.compute.internal" \
      --query 'Reservations[*].Instances[*].{Instance:InstanceId}' \
      --region $AWS_REGION --output text)
    aws ec2 terminate-instances --instance-id ${ec2_instance_id} --region $AWS_REGION > /dev/null
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
    kubectl -n kafka get pod 
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
    echo "Usage: $0 {update-kubeconfig|get-nodes-core|get-nodes-kafka|get-strimzi-pod-sets|get-kafka-pods|get-all-kafka-namespace|apply-kafka-topic|get-kafka-topic|describe-kafka-topic|deploy-kafka-consumer|get-kafka-consumer-producer-steams-pods|verify-kafka-producer|verify-kafka-streams|verify-kafka-consumer|get-cruise-control-pods|apply-kafka-rebalance-manifest|describe-kafka-rebalance|annotate-kafka-rebalance-pod|describe-kafka-partitions|run-perf-test-on-kafka-topic|verify-kafka-consumer-perf-test-topic|view-and-login-to-grafana-dashboard|get-grafana-login-password|create-node-failure|validate-kafka-cluster-pod|verify-consumer-topic-failover-topic|create-test-failover-topic|describe-test-failover-topic|get-test-topic-failover-from-consumer}"
    exit 1
esac
