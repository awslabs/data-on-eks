# Kafka on EKS Auto Mode

An in-workshop Apache Kafka cluster that sits alongside the Spark labs on the **same** EKS Auto Mode cluster created by `analytics/terraform/spark-k8s-operator/`. No extra VPC, no separate cluster, no side install.

Under the hood: the [Strimzi](https://strimzi.io/) operator in KRaft mode (no ZooKeeper), 3 controllers + 3 brokers spread rack-aware across the workshop's three availability zones, plus the usual sidecars — JMX Prometheus exporter, Cruise Control, Kafka Exporter.

## Architecture at a glance

Three design decisions shape this lab. Understanding them up-front makes the rest of the manifest and scripts obvious.

### 1. Kafka runs on a dedicated NodePool, kept away from Spark

Kafka brokers are stateful — each one owns an EBS volume and a set of partition leaderships. Spark executors are stateless and typically run on Spot instances that Karpenter reclaims freely. Co-locating the two means a Spot reclamation event can take a broker with it.

The workshop's Terraform creates a **dedicated Karpenter `NodePool`** for Kafka (see `analytics/terraform/spark-k8s-operator/manifests/automode/nodepool-kafka.yaml` — coming shortly in this PR) that runs **On-Demand only** and carries a `workload=kafka:NoSchedule` taint. The `Kafka` custom resource in this folder carries a matching `toleration`. Nothing else in the workshop cluster tolerates that taint, so nothing else lands on those nodes.

The routing uses **three complementary pieces** on top of Karpenter's usual scheduling:

| Direction | Mechanism | Effect |
|---|---|---|
| Non-Kafka pods **off** the Kafka pool | `workload=kafka:NoSchedule` taint on the NodePool | Scheduler refuses to place them |
| Kafka pods **allowed on** the Kafka pool | Matching toleration on the Kafka pod template | Scheduler accepts placement |
| Kafka pods **routed to** the Kafka pool | `workload: kafka` label on the pool + matching `nodeAffinity` on the pod (Strimzi's PodTemplate schema doesn't accept top-level `nodeSelector`, so we express the same constraint under `affinity.nodeAffinity`) | Karpenter provisions from this pool, not from a higher-weighted general-purpose pool |

The nodeSelector matters as much as the taint. Without it, when a Kafka broker becomes pending, Karpenter picks the highest-weight *feasible* NodePool — since `general-purpose` weight=50 and our Kafka pool has no weight, Kafka would land on general-purpose and the dedicated pool would sit empty. Taint + toleration alone doesn't route.

### 2. Brokers are marked `karpenter.sh/do-not-disrupt`

Voluntary consolidation is a good thing for stateless workloads. For Kafka it isn't.

If Karpenter decides a broker node is underutilized and drains it (as `Balanced` or `WhenEmptyOrUnderutilized` will do), the broker pod restarts on a new node with a fresh PVC attach cycle. During that gap, in-sync replicas (ISR) for every partition led by that broker shrink by one, and any topic with `min.insync.replicas=2` **blocks producers** until the replacement replica catches up.

The pod annotation `karpenter.sh/do-not-disrupt: "true"` on the Kafka pod template tells Karpenter to leave broker nodes alone until they're truly empty. You still get expiry, drift, and forced-disruption paths; you just don't get voluntary bin-packing.

### 3. Rack awareness needs `az_count >= replication_factor`

This cluster deploys topics with `replication.factor = 3` (and `min.insync.replicas = 2`). Kafka's rack-aware placement — and Cruise Control's strict `RackAwareGoal` when you run a rebalance — need **at least as many failure domains (AZs) as replicas**.

The workshop's Terraform ships `az_count = 3` for exactly this reason. If you drop to 2 AZs, brokers still come up (Strimzi spreads them best-effort), topics still work for produce and consume, but Cruise Control rebalance jobs will fail on the strict rack goal:

```
Executor is not ready to rebalance: RackAwareGoal violation: rack count (2) < replication factor (3)
```

Either bump `az_count` back to 3, or switch the rebalance manifest to `RackAwareDistributionGoal` (soft) with `skipHardGoalCheck: true`. The shipped `examples/kafka-rebalance.yaml` assumes the 3-AZ default.

## Prerequisites

The Spark-on-EKS workshop cluster is up (`analytics/terraform/spark-k8s-operator/` deployed) and `kubectl` targets it:

```sh
kubectl get nodes -o wide | head
kubectl get storageclass       # expect: gp3 (default)  ebs.csi.eks.amazonaws.com
```

## Files

```
analytics/kafka/
├── README.md
├── deploy-kafka.sh      # applies kafka-cluster.yaml, waits for the Kafka CR to be Ready
├── cleanup.sh           # removes the Kafka CR, topics, users, PVCs (Terraform owns the operator)
├── kafka-cluster.yaml   # Kafka CR + broker/controller KafkaNodePools + JMX ConfigMap
├── install-strimzi.sh   # fallback operator install for clusters not built by this workshop
└── examples/
    ├── hello-test-topic.yaml   # 3-partition, 3-replica test topic
    └── kafka-rebalance.yaml    # Cruise Control rebalance with strict RackAwareGoal
```

## Deploy

### Confirm the operator is running

The Strimzi Cluster Operator is installed by the workshop's Terraform when `enable_kafka_lab = true` (the default). Confirm it's ready before you apply the Kafka CR:

```sh
kubectl -n kafka rollout status deploy/strimzi-cluster-operator
kubectl get storageclass kafka-gp3
```

Both should be present. If you're on a cluster **not** created by this workshop's Terraform, run `./install-strimzi.sh` first — it applies the operator manifest directly from `https://strimzi.io/install/latest`. (The script uses `kubectl create`, not `apply`, because Strimzi's CRD annotations exceed Kubernetes' `last-applied-configuration` size limit.)

### Apply the Kafka cluster

```sh
./deploy-kafka.sh
```

The Strimzi operator turns `kafka-cluster.yaml` into:

- **3× broker pods** (`cluster-broker-0..2`), each `6 CPU / 58 GiB` request (`8 / 64` limits), `100 GiB` gp3
- **3× controller pods** (`cluster-controller-3..5`), each `1 CPU / 4 GiB` request (`2 / 8` limits), `100 GiB` gp3
- **`entity-operator`** — reconciles `KafkaTopic` and `KafkaUser` CRs
- **`cruise-control`** — analyzes broker load and generates rebalance proposals
- **`kafka-exporter`** — exposes broker/topic metrics for Prometheus

**On the JVM heap.** Each broker gets a small `-Xmx 6g` heap despite the 58 GiB container. That's deliberate: Kafka reads hot data from the **OS page cache**, not from the JVM heap. Giving the JVM 6 GiB and leaving ~50 GiB of page cache is the correct shape for a real-shape broker; growing the heap to fill the container hurts more than it helps (larger heap → longer GC pauses → higher tail latency).

Karpenter provisions 6 On-Demand instances spread across the three workshop AZs — typically `r7g.2xlarge` for the memory-hungry broker pods and `m7g.2xlarge` for the controllers (the NodePool prefers Graviton but keeps `amd64` as a fallback; see [Instance family](#sizing) for why). First deploy takes ~3 minutes end-to-end. When Ready:

```sh
kubectl get kafka -n kafka
kubectl get kafkanodepool -n kafka
kubectl get pods -n kafka
kubectl get nodeclaims -l workload=kafka
```

Bootstrap servers (internal-only, cluster-local DNS):

- Plain: `cluster-kafka-bootstrap.kafka.svc:9092`
- TLS:   `cluster-kafka-bootstrap.kafka.svc:9093`

## Verify

Create a test topic:

```sh
kubectl apply -f examples/hello-test-topic.yaml
kubectl get kafkatopic -n kafka
```

Produce three messages using `kafka-console-producer.sh` from Strimzi's client image (image tag matches the Kafka version in the CR):

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

Expected:

```
msg-1
msg-2
msg-3
```

## Cruise Control rebalance (optional)

Cruise Control watches broker load and generates rebalance proposals against a set of goals (rack awareness, replica capacity, disk capacity, CPU distribution, leader balance). Submit a rebalance:

```sh
kubectl apply -f examples/kafka-rebalance.yaml
kubectl get kafkarebalance rebalance -n kafka -w
```

The CR transitions `PendingProposal → ProposalReady`. When it reaches `ProposalReady`, approve:

```sh
kubectl annotate kafkarebalance rebalance -n kafka \
  strimzi.io/rebalance=approve --overwrite
```

Then it goes `Rebalancing → Ready`.

The manifest uses strict `RackAwareGoal`, which requires `az_count >= replication_factor`. See [Architecture #3](#3-rack-awareness-needs-az_count--replication_factor) — if you dropped `az_count` to 2, this will fail.

## Cleanup

```sh
./cleanup.sh
```

Removes the Kafka CR, KafkaTopics, KafkaUsers, KafkaRebalances, KafkaNodePools, and the broker/controller PVCs (broker data is deleted). The Strimzi operator, the `kafka-gp3` StorageClass, the dedicated Kafka NodePool, and the `kafka` namespace stay in place — those are owned by Terraform and go away with `terraform destroy` when you tear down the workshop.

## Storage tiers

**Kafka is throughput-bound, not IOPS-bound.** Brokers write sequentially and read the stream tip from the OS page cache, so the metric that actually matters for broker storage is *provisioned throughput per volume*. The AWS Kafka-on-EBS guidance is to match the volume's provisioned throughput to the instance's EBS baseline — a bigger instance without provisioned throughput won't run any faster.

Broker/controller PVs bind to the `kafka-gp3` StorageClass created by Terraform. That's a **gp3 volume with 6000 IOPS and 1000 MiB/s throughput per volume** — the gp3 throughput ceiling, and enough to keep pace with any of the `m7g/r7g` instance sizes the Kafka NodePool provisions.

Three ways to change the storage tier for a heavier workload:

| Tier | Latency | Peak throughput / volume | Best for | Trade-off |
|---|---|---|---|---|
| **`kafka-gp3` (default)** | ~1 ms | 1000 MiB/s | Workshop, dev, small–mid prod | Hits gp3 ceiling — can't push further per volume |
| **`st1`** (HDD, data-volume only) | 5–10 ms | 500 MiB/s | High-throughput sequential logs, cost-sensitive clusters | Read latency on cold partitions; **cannot be a root volume** |
| **`io2` Block Express** | sub-ms | 4000 MiB/s | Prod, latency-sensitive | ~10× the cost of gp3 — benchmark against gp3-at-1000 first |

To switch tiers, create an alternate StorageClass and point the KafkaNodePool storage spec at it. For `io2` Block Express:

```yaml
# analytics/terraform/spark-k8s-operator/manifests/automode/storageclass-kafka-io2.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata: { name: kafka-io2 }
provisioner: ebs.csi.eks.amazonaws.com
volumeBindingMode: WaitForFirstConsumer
parameters:
  type: io2
  iops: "20000"
  fsType: xfs
  encrypted: "true"
```

Then in `kafka-cluster.yaml`, change `class: kafka-gp3` → `class: kafka-io2`.

## Sizing

Rules of thumb from AWS's Kafka-on-EBS guidance, worth knowing before you touch the resource requests in `kafka-cluster.yaml`:

- **Target 80% of the theoretical throughput limit** — leave headroom for spikes, GC pauses, and partition rebalances.
- **Scale out for writes, scale up for readers.** More brokers = higher aggregate write throughput and smaller blast radius per broker failure. Larger instances = more page cache for lagging consumers and more consumer groups per broker.
- **Memory is page cache, not heap.** Reads from the stream tip come from RAM (no EBS I/O). Lagging consumers force slow non-sequential EBS reads — more RAM mitigates this, which is why the broker container requests 58 GiB even though `-Xmx = 6g`.
- **Keep broker CPU below ~60%.** In-cluster TLS encryption adds notable p99 latency; if you turn it on, size up (`r7g.4xlarge` or larger) to reclaim that headroom.
- **Instance-EBS bandwidth is the ceiling.** `m7g.2xlarge → m7g.4xlarge` gives *no* throughput gain at default gp3 settings because the volume caps out first. That's why this lab ships gp3 provisioned at 1000 MiB/s — matches the instance's EBS baseline on 4xlarge and up.

CloudWatch metrics worth alerting on for a production-shape broker:

- `VolumeReadOps` / `VolumeWriteOps` and `VolumeThroughputPercentage` (gp3 throughput headroom)
- `BurstBalance` (gp2 leftovers, though we're on gp3)
- EC2 `EBSIOBalance%` and `EBSByteBalance%` — the instance-level EBS credits
- Kafka JMX: `BytesInPerSec`, `BytesOutPerSec`, `UnderReplicatedPartitions`, `ISRShrinksPerSec`

## Extending

- **Broker count** — raise `spec.replicas` on the `broker` pool. Keep controller replicas **odd** (3, 5, 7) — KRaft quorum needs a majority. Scale out here rather than up when write throughput is the bottleneck (see [Sizing](#sizing)).
- **Instance family** — the Kafka NodePool prefers `m7g/r7g` (Graviton3), the AWS-validated Kafka-on-EBS benchmark family. If you need lowest-latency storage, look at `i8g` (Graviton4 + NVMe instance store) — but note the instance-store trade-off: broker data is lost on node failure and forces a full replication from peers.
- **Kafka version** — the Strimzi operator version pins the supported Kafka range. Bumping the `version` in the CR without a matching `strimzi_operator_version` variable in Terraform will fail validation on `apply`. See [Strimzi's version matrix](https://strimzi.io/downloads/).
- **Smaller broker footprint for pure demos** — drop `spec.kafka.resources.requests` to `2 CPU / 8 GiB` and `spec.storage.volumes[0].size` to `20 GiB` per pool. Loses the page-cache-oriented shape but ~⅕ of the cost. Karpenter will pack onto smaller instances (`m*.xlarge` rather than `r*.2xlarge`).
- **Disable the operator install** — set `enable_kafka_lab = false` in Terraform. The Strimzi operator and `kafka-gp3` StorageClass are no longer created; the Kafka Karpenter NodePool remains (harmless — nothing tolerates its taint).
