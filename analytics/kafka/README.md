# Kafka on EKS Auto Mode (Strimzi)

A workshop-ready Apache Kafka cluster running on the Spark-on-EKS Auto Mode cluster, deployed via the [Strimzi](https://strimzi.io/) operator in **KRaft mode** (no ZooKeeper).

The shipped configuration runs **3 controllers + 3 brokers** with rack-aware placement across availability zones, JMX Prometheus metrics, Cruise Control, and the Kafka Exporter.

## Why this folder?

The workshop's Spark labs already use the EKS Auto Mode cluster created by `analytics/terraform/spark-k8s-operator/`. This folder adds an interactive Kafka lab on top of that same cluster — no additional infrastructure required. You install the operator, deploy the Kafka custom resources, and run a smoke test.

## Prerequisites

- The Spark-on-EKS workshop cluster is already running (you've completed the bootstrap that the workshop CFN does on your IDE).
- `kubectl` is configured against the cluster:
  ```sh
  kubectl get nodes
  ```
- The default `gp3` StorageClass exists (the workshop's Terraform already creates it):
  ```sh
  kubectl get storageclass
  ```
  You should see `gp3 (default)` with provisioner `ebs.csi.eks.amazonaws.com`.

## Layout

```
analytics/kafka/
├── README.md                       # this file
├── install-strimzi.sh             # installs the latest Strimzi operator
├── kafka-cluster.yaml             # Kafka CR + KafkaNodePools + JMX ConfigMap
├── deploy-kafka.sh                # applies the cluster and waits for Ready
├── cleanup.sh                     # tears everything down
└── examples/
    ├── hello-test-topic.yaml      # 3-partition, 3-replica test topic
    └── kafka-rebalance.yaml       # Cruise Control rebalance demo
```

## Step 1: Install the Strimzi operator

The Strimzi Cluster Operator is the controller that watches for `Kafka`, `KafkaNodePool`, `KafkaTopic`, and other Strimzi CRs and provisions the corresponding workloads.

```sh
./install-strimzi.sh
```

This creates the `kafka` namespace and applies the latest Strimzi install bundle directly from `https://strimzi.io/install/latest?namespace=kafka`. The script waits for `deploy/strimzi-cluster-operator` to be Ready (typically under a minute).

> **Note:** the script uses `kubectl create` rather than `kubectl apply` because the Strimzi install bundle contains CRDs whose annotations exceed Kubernetes' size limit for `last-applied-configuration`.

## Step 2: Deploy the Kafka cluster

```sh
./deploy-kafka.sh
```

This applies `kafka-cluster.yaml` which contains:

- A `Kafka` resource named `cluster` (KRaft mode, Kafka 4.0.0, plain + TLS internal listeners, rack-aware)
- A `KafkaNodePool` named `controller` with **3 controller replicas**, 100 Gi gp3 each
- A `KafkaNodePool` named `broker` with **3 broker replicas**, 100 Gi gp3 each
- A `ConfigMap` with the JMX Prometheus exporter rules
- The `entityOperator` (for `KafkaTopic` / `KafkaUser` reconciliation), `cruiseControl`, and `kafkaExporter` all enabled

Each broker requests 6 CPU / 58 Gi memory (limit 8 CPU / 64 Gi). On Auto Mode, this typically pulls **6 × `r5a.4xlarge` instances** (one per broker/controller) over 3 availability zones thanks to the `rack` and `topologySpreadConstraints` settings. The first deploy takes around 3 minutes once Karpenter has provisioned nodes.

When complete you should see:

```console
NAME                             READY   METADATA STATE   WARNINGS
kafka.kafka.strimzi.io/cluster   True
NAME                                        DESIRED REPLICAS   ROLES            NODEIDS
kafkanodepool.kafka.strimzi.io/broker       3                  ["broker"]       [0,1,2]
kafkanodepool.kafka.strimzi.io/controller   3                  ["controller"]   [3,4,5]

cluster-broker-0          1/1   Running
cluster-broker-1          1/1   Running
cluster-broker-2          1/1   Running
cluster-controller-3      1/1   Running
cluster-controller-4      1/1   Running
cluster-controller-5      1/1   Running
cluster-cruise-control-*  1/1   Running
cluster-entity-operator-* 2/2   Running
cluster-kafka-exporter-*  1/1   Running
```

Bootstrap servers in the cluster:

- Plain: `cluster-kafka-bootstrap.kafka.svc:9092`
- TLS: `cluster-kafka-bootstrap.kafka.svc:9093`

## Step 3: Smoke test

Create a topic:

```sh
kubectl apply -f examples/hello-test-topic.yaml
kubectl get kafkatopic -n kafka
```

Produce 3 messages (the `quay.io/strimzi/kafka` image ships with `kafka-console-*` scripts):

```sh
kubectl run kafka-producer-test -n kafka --rm -i --restart=Never \
  --image=quay.io/strimzi/kafka:latest-kafka-4.0.0 \
  -- bash -c 'echo -e "msg-1\nmsg-2\nmsg-3" | /opt/kafka/bin/kafka-console-producer.sh \
    --bootstrap-server cluster-kafka-bootstrap:9092 --topic hello-test'
```

Consume them back:

```sh
kubectl run kafka-consumer-test -n kafka --rm -i --restart=Never \
  --image=quay.io/strimzi/kafka:latest-kafka-4.0.0 \
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

The `Kafka` CR enables Cruise Control, which can rebalance partitions across brokers. To trigger an analysis:

```sh
kubectl apply -f examples/kafka-rebalance.yaml
kubectl get kafkarebalance rebalance -n kafka -w
```

The CR transitions through `PendingProposal` → `ProposalReady`. When `ProposalReady`, you can approve it:

```sh
kubectl annotate kafkarebalance rebalance -n kafka \
  strimzi.io/rebalance=approve --overwrite
```

It then transitions to `Rebalancing` → `Ready`.

## Step 4: Tear down

When you're done with the lab:

```sh
./cleanup.sh
```

This removes all Kafka topics/users, the Kafka CR, the KafkaNodePools, the broker/controller PVCs (broker data is deleted), the Strimzi operator, and the `kafka` namespace.

## What you learned

- How to install the Strimzi operator on an existing EKS Auto Mode cluster.
- How to declare a KRaft-mode Kafka cluster with `KafkaNodePool` (the post-StatefulSet abstraction Strimzi uses for elastic broker pools).
- How rack awareness + topology spread constraints + pod anti-affinity combine to spread brokers across AZs.
- How to produce/consume from inside the cluster.
- How Cruise Control fits into a Strimzi-managed Kafka cluster.

## Customizing

- **Storage size**: change `spec.storage.volumes[0].size` in each `KafkaNodePool` (default 100 Gi).
- **Broker count**: change `spec.replicas` on the `broker` and `controller` node pools (defaults 3 + 3). Keep controller replicas odd to maintain KRaft quorum.
- **Resource request/limits**: edit `spec.kafka.resources` on the `Kafka` CR. Smaller dev sizes (e.g. 2 CPU / 8 Gi) work fine for hello-world testing and let Karpenter consolidate onto smaller instances.
- **Storage class**: the manifest uses `class: gp3`. To experiment with NVMe-backed local storage, look at the [EC2 Instance Store CSI driver](https://docs.aws.amazon.com/eks/latest/userguide/lis-csi.html) — but note it does **not** work with Auto Mode today.
