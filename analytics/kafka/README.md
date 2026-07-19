# Kafka on EKS Auto Mode (Strimzi)

A workshop-ready Apache Kafka cluster running on the Spark-on-EKS Auto Mode cluster, deployed with the [Strimzi](https://strimzi.io/) operator in **KRaft mode** (no ZooKeeper).

The shipped configuration runs **3 controllers + 3 brokers** with rack-aware placement across availability zones, JMX Prometheus metrics, Cruise Control, and the Kafka Exporter — right-sized for a workshop.

## How this fits the workshop

This lab runs on the **same EKS Auto Mode cluster** created by `analytics/terraform/spark-k8s-operator/` — no separate infrastructure.

The Terraform stack (with `enable_kafka = true`, the default) provisions two things up front:

1. The **Strimzi Cluster Operator** (Helm), into the `kafka` namespace.
2. A **dedicated Kafka NodePool** (`NodeGroupType=KafkaBroker`, On-Demand), isolated from the Spark NodePools.

The **Kafka cluster itself is deployed by you during the lab** (`deploy-kafka.sh`), so broker nodes are only provisioned when you actually run it. This keeps idle cost off attendees who don't reach this lab.

## Versions

| Component | Version | Notes |
|-----------|---------|-------|
| Strimzi Cluster Operator | **1.1.0** | `v1` CRD API; supports Kafka 4.3.0 |
| Apache Kafka | **4.3.0** (`metadataVersion 4.3-IV0`) | KRaft mode |
| Client/CLI image | `quay.io/strimzi/kafka:latest-kafka-4.3.0` | must match the cluster version |

> The Strimzi operator version is set by the `strimzi_operator_version` Terraform variable. If you change the Kafka `version` in `kafka-cluster.yaml`, make sure the operator version supports it and update the client image tag in the smoke test to match.

## Prerequisites

- The Spark-on-EKS workshop cluster is running and `kubectl` is configured:
  ```sh
  kubectl get nodes
  ```
- The Strimzi operator is installed (Terraform did this when `enable_kafka = true`):
  ```sh
  kubectl -n kafka rollout status deploy/strimzi-cluster-operator
  ```
- The default `gp3` StorageClass exists (created by the workshop Terraform):
  ```sh
  kubectl get storageclass
  ```

## Layout

```
analytics/kafka/
├── README.md              # this file
├── kafka-cluster.yaml     # Kafka CR + KafkaNodePools + JMX metrics ConfigMap
├── deploy-kafka.sh        # applies the cluster and waits for Ready
├── cleanup.sh             # tears down the in-lab Kafka cluster (not the operator)
└── examples/
    ├── hello-test-topic.yaml   # 3-partition, 3-replica test topic
    └── kafka-rebalance.yaml    # Cruise Control rebalance demo
```

## Step 1: Deploy the Kafka cluster

```sh
./deploy-kafka.sh
```

This applies `kafka-cluster.yaml`, which contains:

- A `Kafka` resource named `cluster` (KRaft mode, Kafka 4.3.0, plain + TLS internal listeners, rack-aware), pinned to the dedicated `KafkaBroker` NodePool with `karpenter.sh/do-not-disrupt` so brokers are not consolidated.
- A `KafkaNodePool` named `controller` with **3 replicas** (1 CPU / 2-4 Gi, 20 Gi gp3 each).
- A `KafkaNodePool` named `broker` with **3 replicas** (1-2 CPU / 6-8 Gi, 20 Gi gp3 each).
- A `ConfigMap` with the JMX Prometheus exporter rules.
- The `entityOperator`, `cruiseControl`, and `kafkaExporter` enabled.

Bootstrap servers in the cluster:

- Plain: `cluster-kafka-bootstrap.kafka.svc:9092`
- TLS: `cluster-kafka-bootstrap.kafka.svc:9093`

## Step 2: Smoke test

Create a topic:

```sh
kubectl apply -f examples/hello-test-topic.yaml
kubectl get kafkatopic -n kafka
```

Produce 3 messages:

```sh
kubectl run kafka-producer-test -n kafka --rm -i --restart=Never \
  --image=quay.io/strimzi/kafka:latest-kafka-4.3.0 \
  -- bash -c 'echo -e "msg-1\nmsg-2\nmsg-3" | /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server cluster-kafka-bootstrap:9092 --topic hello-test'
```

Consume them back:

```sh
kubectl run kafka-consumer-test -n kafka --rm -i --restart=Never \
  --image=quay.io/strimzi/kafka:latest-kafka-4.3.0 \
  -- bash -c '/opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server cluster-kafka-bootstrap:9092 --topic hello-test \
  --from-beginning --timeout-ms 10000'
```

Expected output:

```console
msg-1
msg-2
msg-3
```

## Optional: Cruise Control rebalance

```sh
kubectl apply -f examples/kafka-rebalance.yaml
kubectl get kafkarebalance rebalance -n kafka -w
```

When it reaches `ProposalReady`, approve it:

```sh
kubectl annotate kafkarebalance rebalance -n kafka \
  strimzi.io/rebalance=approve --overwrite
```

## Step 3: Tear down

When you're done with the lab:

```sh
./cleanup.sh
```

This removes the Kafka topics/users/rebalances, the Kafka CR, the KafkaNodePools, and the broker/controller PVCs. It does **not** uninstall the Strimzi operator or the Kafka NodePool — those are managed by Terraform and removed by the workshop teardown (`terraform destroy`).

## What you learned

- How the Strimzi operator runs on an existing EKS Auto Mode cluster.
- How to declare a KRaft-mode Kafka cluster with `KafkaNodePool` and pin it to a dedicated, On-Demand NodePool isolated from Spark.
- How rack awareness + topology spread + pod anti-affinity spread brokers across AZs.
- How to produce/consume from inside the cluster, and how Cruise Control rebalances partitions.

## Customizing

- **Broker/controller count**: `spec.replicas` on each `KafkaNodePool` (keep controllers odd for KRaft quorum).
- **Resources**: `spec.resources` on each `KafkaNodePool`.
- **Storage**: `spec.storage.volumes[0].size` (default 20 Gi, `class: gp3`).
- **Kafka version**: `spec.kafka.version` / `metadataVersion` on the `Kafka` CR — keep it within the range the installed Strimzi operator supports, and update the client image tag in the smoke test.
