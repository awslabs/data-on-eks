---
title: Cluster Mode
sidebar_position: 5
---

# Valkey Cluster Mode on EKS

Cluster mode shards data across multiple primaries using hash-slot partitioning and gossip-based failure detection. This stack ships a **local Helm chart** (`data-stacks/valkey-on-eks/examples/cluster-mode-helm-chart/`) that deploys a production-grade cluster onto the data-on-eks Valkey NodePool, with no operator and no external chart dependency.

The chart will be retired in favor of the upstream `valkey-io/valkey-helm` chart once cluster mode lands there ([valkey-helm #18](https://github.com/valkey-io/valkey-helm/issues/18)).

This guide covers:

1. When to use cluster mode and how it differs from replication mode.
2. How the cluster communicates internally — gossip, replication, slot routing, failover.
3. Choosing instance types, storage, and scale.
4. Deployment, verification, and day-2 operations.

## When to Use Cluster Mode

Use cluster mode when at least one of these holds:

- **Working set > single node memory.** Your data exceeds what a single `r7g.16xlarge` (~512 GiB) can hold, or you want to keep per-node memory pressure down for fork-time CoW headroom during BGSAVE.
- **Write throughput > single primary.** Replication mode has one primary; all writes serialize through it. Cluster mode shards writes across N primaries.
- **Multi-key operations are NOT a hard requirement.** Cluster mode rejects multi-key commands (`MGET`, `MSET`, `RENAME`, transactions, Lua) when keys span different slots — the application must use [hash tags](https://valkey.io/topics/cluster-spec/#hash-tags) (`{user:1}:profile` and `{user:1}:settings` hash to the same slot) or accept per-key operations.

If your dataset fits a single large-memory node and the workload is read-heavy, **stay on replication mode**. Cluster mode adds operational complexity that's only worth it for scale.

| Factor | Replication Mode | Cluster Mode |
|---|---|---|
| Topology | 1 primary + N replicas | 3+ primaries × 1+ replica each (minimum 6 pods) |
| Write scaling | ✗ — single primary | ✓ — sharded by hash slot |
| Multi-key ops | ✓ — single keyspace | Same-slot only (use hash tags) |
| Failover | Manual `REPLICAOF NO ONE` | Automatic via gossip (~10s detect + promote) |
| Min nodes (HA) | 2 | 6 (3 primaries + 3 replicas) |
| Operational surface | Lower | Higher (gossip, slot rebalancing, MEET/FORGET) |
| Chart support | ✓ Official `valkey-io/valkey-helm` | This stack's local chart until [#18](https://github.com/valkey-io/valkey-helm/issues/18) lands |

## Architecture

```
┌─────────────────────────── EKS Cluster ────────────────────────────┐
│                                                                    │
│  AZ us-west-2a            AZ us-west-2b           AZ us-west-2c    │
│  ┌──────────────┐         ┌──────────────┐        ┌──────────────┐ │
│  │ valkey-c-0   │         │ valkey-c-2   │        │ valkey-c-1   │ │
│  │ primary      │         │ primary      │        │ primary      │ │
│  │ slots 0-5460 │         │ slots 10923- │        │ slots 5461-  │ │
│  │              │         │       16383  │        │       10922  │ │
│  └──────────────┘         └──────────────┘        └──────────────┘ │
│         ▲                        ▲                       ▲         │
│         │ async replication      │                       │         │
│         │ (TCP 6379, PSYNC)      │                       │         │
│  ┌──────┴───────┐         ┌──────┴───────┐        ┌──────┴───────┐ │
│  │ valkey-c-3   │         │ valkey-c-5   │        │ valkey-c-4   │ │
│  │ replica of   │         │ replica of   │        │ replica of   │ │
│  │ valkey-c-1   │         │ valkey-c-0   │        │ valkey-c-2   │ │
│  └──────────────┘         └──────────────┘        └──────────────┘ │
│                                                                    │
│  Cluster bus (gossip) — TCP 16379, full mesh between all 6 pods   │
│  Headless Service: valkey-cluster-headless                         │
│   ├─ valkey-cluster-0.valkey-cluster-headless.<ns>.svc...:6379     │
│   ├─ valkey-cluster-1...                                           │
│   └─ valkey-cluster-5...    (per-pod stable DNS, hostname-aware)   │
└────────────────────────────────────────────────────────────────────┘
```

Three concepts make cluster mode work — **slots**, **gossip**, **replication**. Each pod owns a piece of each.

## How the cluster communicates internally

Operators need this model to debug effectively. Two TCP ports per pod, three different protocols on top.

### Hash slots and client routing (port 6379)

Every key is hashed into one of **16,384 slots** via CRC16(key) mod 16384. Each primary owns a contiguous range; with three shards the default split is:

| Shard | Primary pod (in our test cluster) | Slot range |
|---|---|---|
| 0 | `valkey-cluster-0` | 0 – 5460 |
| 1 | `valkey-cluster-2` | 10923 – 16383 |
| 2 | `valkey-cluster-1` | 5461 – 10922 |

When a **cluster-aware client** (Lettuce, Jedis, ioredis, redis-py ≥ 4.1, go-redis, valkey-glide) connects:

1. It issues `CLUSTER SHARDS` (or `CLUSTER NODES` on older clients) to learn the slot → primary map.
2. For each command, it computes the slot from the key and routes the connection directly to the owning primary.
3. If the slot ownership has changed since the cached map (e.g., during a reshard), the targeted primary returns `MOVED <slot> <new-host>:<port>` or `ASK <slot> <new-host>:<port>`. The client updates its map and retries.

`MOVED` is permanent (slot has moved); `ASK` is transient (slot is mid-migration, the next single request should go to the new host). A non-cluster-aware client will hit `MOVED` on every cross-slot command and fail.

[Hash tags](https://valkey.io/topics/cluster-spec/#hash-tags) let you co-locate keys onto the same slot. `{user:42}:profile` and `{user:42}:orders` share slot CRC16("user:42") % 16384, so `MGET {user:42}:profile {user:42}:orders` works inside a single shard.

### Gossip — the cluster bus (port 16379)

Every pod opens a TCP connection to every other pod on port 16379. This is the **cluster bus**. With 6 pods that's 15 connections; with 100 pods it's 4,950. The bus carries small binary messages — never application data.

What gossip does:

- **Failure detection.** Each pod sends `PING` to a few random peers every second. The recipient replies `PONG`. If a pod doesn't get a `PONG` within `cluster-node-timeout` (default 15s), it marks the peer as `PFAIL` (possible failure) and gossips that opinion. When the *majority* of primaries agree a peer is `PFAIL`, it transitions to `FAIL` and replicas of the dead primary start a failover election.
- **Topology propagation.** Every gossip exchange piggybacks the sender's view of a random subset of nodes. New nodes joined via `CLUSTER MEET` get discovered transitively — you only need to introduce one new pod to one existing pod, the rest learn via gossip.
- **Configuration epoch.** Each primary has a monotonic epoch. When a replica promotes to primary, its epoch increments. The cluster uses epochs to resolve conflicting slot-ownership claims after a partition heals.

> "For example in a 100 node cluster with a node timeout set to 60 seconds, every node will try to send 99 pings every 30 seconds … 330 pings per second in the total cluster."
> — [Valkey Cluster Specification](https://valkey.io/topics/cluster-spec/)

Gossip is intentionally cheap. Raising `cluster-node-timeout` halves heartbeat traffic at the cost of doubling failure-detection latency. Default 15s is fine up to ~500 pods. Above 500, bump to 30s.

### Replication — primary → replica (port 6379, PSYNC)

Each replica maintains a single long-lived TCP connection to its primary on the client port. The connection runs the **PSYNC** protocol:

1. **Initial full sync**: replica connects, primary takes a BGSAVE snapshot (or uses a diskless transfer), streams it over the wire, then catches up via the replication backlog.
2. **Partial resync**: if the replica disconnects briefly, on reconnect it tells the primary its current replication offset. If the offset is still in the primary's backlog (default `repl-backlog-size 10mb`), the primary streams just the diff. Otherwise it falls back to full sync.

Auth: the replica authenticates to the primary using `primaryauth` (Valkey 8.0 rename of `masterauth`) from `/data/conf/auth.conf`. This chart uses **`requirepass` + `primaryauth` with the same password** — replicas connect as the `default` user. No separate ACL file.

Replication is **asynchronous** in Valkey by default. A write `SET k v` on a primary returns OK to the client *before* the replica has received it. If the primary dies in that 1-2 ms window, the unacknowledged write is lost. For stronger consistency use `WAIT N timeout` (blocks until N replicas ack) — but understand cluster mode tolerates async lag deliberately, and `WAIT` only helps within a single shard.

### Hostname-aware addressing

This chart sets `cluster-preferred-endpoint-type hostname` and announces each pod's per-pod DNS name (`valkey-cluster-N.valkey-cluster-headless.<ns>.svc.cluster.local`) via `cluster-announce-hostname`. Result: when a pod restarts and gets a new IP, the cluster's gossip table updates the IP under the same hostname, and clients re-resolve via DNS rather than getting stuck on a stale IP.

## Choosing instance types

Valkey is RAM-bound. The right defaults look almost exactly like what ElastiCache offers under the hood for Valkey nodes.

### What ElastiCache uses (managed)

ElastiCache exposes `cache.*` SKUs that map to standard EC2 families. For Valkey, the recommended families are:

| Family | Use case |
|---|---|
| `cache.r7g`, `cache.r8g` | **Default** for Valkey — memory-optimized, Graviton, ~8 GiB RAM per vCPU |
| `cache.m7g`, `cache.m6g` | General-purpose — smaller datasets (under 8 GiB/shard), CPU-bound clients |
| `cache.r6gd` | Memory-optimized **with local NVMe** for [data tiering](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/data-tiering.html) (hot/warm tier inside the node) |
| `cache.c7gn` | Network-optimized — proxies, counters, rate-limiters with very high QPS |
| `cache.t4g` | **Dev/test only** — burstable CPU credits are incompatible with Valkey's single-threaded command loop |

AWS [announced](https://aws.amazon.com/about-aws/whats-new/2023/08/amazon-elasticache-m7g-r7g-graviton-3-nodes/) for ElastiCache on r7g: *"up to 28% increased throughput, up to 21% improved P99 latency, up to 25% higher networking bandwidth"* vs r6g.

### What to use on self-managed EKS

**R-family (memory-optimized) is the default.** The data-on-eks Valkey NodePool ([`nodepool-valkey.yaml`](https://github.com/awslabs/data-on-eks/blob/main/infra/terraform/manifests/karpenter/nodepool-valkey.yaml)) is preconfigured for `r7g` and `r8g` Graviton instances.

**Graviton vs x86.** Valkey upstream officially supports ARM64 and ran its own [1M RPS benchmark](https://valkey.io/blog/unlock-one-million-rps/) on `c7g.16xlarge`. Independent benchmarks measure ~22% lower latency on Graviton vs equivalent x86 SKUs. Fork/BGSAVE is also cheaper on Graviton because its TLB / page-walker handles COW patterns more efficiently. **Use Graviton unless you have a hard x86 dependency** (e.g., a kernel module).

**Size per shard** (reserve ~25% for fork-time CoW headroom per AWS [BGSAVE best practice](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/BestPractices.BGSAVE.html)):

| Working set per shard | Suggested instance | Pod memory request/limit | `maxmemory` |
|---|---|---|---|
| 12 GiB | `r7g.large` (16 GiB) | 12 Gi / 16 Gi | `12gb` |
| 24 GiB | `r7g.xlarge` (32 GiB) | 24 Gi / 30 Gi | `24gb` |
| 64 GiB | `r7g.2xlarge` (64 GiB) | 48 Gi / 60 Gi | `48gb` |
| 128 GiB | `r7g.4xlarge` (128 GiB) | 96 Gi / 120 Gi | `96gb` |
| 256 GiB | `r7g.8xlarge` (256 GiB) | 192 Gi / 240 Gi | `192gb` |
| > 256 GiB | **Shard horizontally instead** — fork on a 512 GiB heap is operationally painful even with overcommit + THP disabled. |

Always set `requests.memory == limits.memory`; otherwise the node OOM-killer can target the BGSAVE child during a fork. The chart enforces this in the default `values.yaml`.

**Avoid:**

- **T-family** (burstable). The CPU credits model is incompatible with Valkey's single-threaded event loop and unpredictable under spikes. AOF is unsupported on T2 per AWS docs.
- **Spot instances for primaries.** The 2-minute interruption notice is not enough for a clean shard hand-off; replica resync after each interruption burns network bandwidth. Spot is acceptable only for read-replica overflow pools.

### Network bandwidth

Sustained replication + gossip + client traffic adds up fast. A 3-replica shard at 100k ops/sec, 1 KB values pushes ~800 Mbps of client traffic alone; full-sync of a 64 GiB replica can saturate a NIC for minutes. Plan for **2× peak steady-state**:

| Sustained throughput | Minimum instance |
|---|---|
| < 2.5 Gbps | `r7g.xlarge` (baseline 1.876 Gbps, burst 12.5 Gbps) |
| 2.5 – 10 Gbps | `r7g.4xlarge` (baseline 7.5 Gbps) |
| > 10 Gbps | `r7g.8xlarge`+ or **r7gn / m7gn** network-optimized variants (25 Gbps baseline) |

Enable **VPC CNI prefix delegation** (`ENABLE_PREFIX_DELEGATION=true`) for dense Valkey deployments — each ENI gets `/28` prefixes (16 IPs) instead of secondary IPs, and `r7g.16xlarge` jumps from 234 to 737 pods per node. The data-on-eks infra stack ships this enabled by default.

### Cost

- **Compute Savings Plans (3-yr)** are the recommended baseline — ~66% discount with flexibility to move between sizes/families. AWS itself [recommends them](https://docs.aws.amazon.com/savingsplans/latest/userguide/sp-ris.html) over RIs *"because they offer similar savings with more flexibility."*
- For a 6-pod `r7g.2xlarge` cluster in us-west-2: ~$17,650/year on-demand → ~$6,000/year on a 3-yr Compute SP.
- **Don't run primaries on Spot.** Replica overflow pools, yes. Primaries, no.

## Choosing storage

The per-pod PVC carries AOF, RDB, and `nodes.conf` (cluster state). Its specs directly drive AOF write latency, BGSAVE / AOF-rewrite throughput, and PSYNC full-resync speed.

### gp3 is the right default

> "gp3 volumes deliver a consistent baseline IOPS performance of 3,000 IOPS… you can provision additional IOPS (up to a maximum of 80,000)… at a ratio of 500 IOPS per GiB."
> — [AWS EBS docs](https://docs.aws.amazon.com/ebs/latest/userguide/general-purpose.html)

Critically, *"gp3 volumes do not use burst performance. They can indefinitely sustain their full provisioned IOPS and throughput."* This is why gp3 displaced gp2 for Valkey — AOF rewrite is a sustained sequential write that would drain a gp2 burst balance.

| Working set per shard | PVC size | gp3 IOPS | gp3 throughput | StorageClass |
|---|---|---|---|---|
| ≤ 12 GiB | 64 GiB | 3,000 (baseline) | 125 MiB/s (baseline) | default `gp3` |
| 12 – 64 GiB | 200 GiB | 6,000 | 500 MiB/s | `valkey-gp3` (example below) |
| 64 – 256 GiB | 800 GiB | 12,000 | 750 MiB/s | custom gp3 |
| > 256 GiB OR p99-sensitive | 1+ TiB | up to 16,000 / 1,000 MiB/s (gp3 ceiling) | — | upgrade to **io2 Block Express** |

PVC size = ~3× working set: current AOF + rewritten AOF + RDB snapshot must coexist during a rewrite.

### When to step up from gp3

**io2 Block Express** when AOF p99 latency on gp3 (1–3 ms typical) is unacceptable. AWS describes it as *"designed to deliver an average latency of under 500 microseconds for 16 KiB I/O operations, reducing the frequency of I/Os exceeding 800 microseconds by over 10×"*. Premium is ~3–5× gp3. **Do not enable Multi-Attach** — each Valkey pod owns its own shard; sharing a volume violates the single-writer assumption and corrupts `nodes.conf` and AOF.

**Local NVMe instance store (`r6gd`/`r7gd`)** for ultra-low-latency caches where occasional resync is acceptable. In this chart you'd use the `local-storage` StorageClass and accept that pod rescheduling = total data loss for that pod, then rely on replica resync. ElastiCache uses NVMe internally only for [data tiering](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/data-tiering.html), not primary persistence.

**Never EFS/FSx.** AOF is latency-sensitive small-IO; NFS `fsync` latencies are an order of magnitude worse than EBS, and `nodes.conf` rename semantics over NFS have caused real corruption in production. Block storage only.

### The `valkey-gp3` StorageClass

This stack ships a higher-spec gp3 StorageClass example at [`data-stacks/valkey-on-eks/examples/storageclass-valkey-gp3.yaml`](https://github.com/awslabs/data-on-eks/blob/main/data-stacks/valkey-on-eks/examples/storageclass-valkey-gp3.yaml):

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: valkey-gp3
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  iops: "6000"           # 2× gp3 baseline
  throughput: "500"      # 4× gp3 baseline
  encrypted: "true"
  fsType: xfs            # better than ext4 for sustained AOF rewrites > 50 GiB
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
```

Apply once per cluster:

```bash
kubectl apply -f data-stacks/valkey-on-eks/examples/storageclass-valkey-gp3.yaml
```

Then in the chart values:

```yaml
persistence:
  storageClass: valkey-gp3
  size: 200Gi
```

### Filesystem and mount tuning

- **xfs** for shards > 50 GiB — better large-sequential-write throughput than ext4. The `valkey-gp3` StorageClass uses xfs.
- **`noatime,nodiratime`** mount options eliminate a metadata write per AOF read (matters during PSYNC).
- **Do not enable** `data=journal` on ext4 — doubles write amplification on AOF.

### When to skip persistence entirely

For pure caches (data reconstructible from an upstream source-of-truth) set `appendonly no` and `save ""`. Operationally:

- Pod restart = empty shard. In cluster mode with replicas, the primary failover promotes a replica with the data still in RAM; the restarted pod becomes empty and triggers a full resync.
- Set `cluster-require-full-coverage no` (already the chart default) so a single empty shard doesn't block the whole cluster.
- Drop the PVC entirely (`persistence.enabled: false`) — `emptyDir` will be used and `nodes.conf` is regenerated on cluster join.
- Removes BGSAVE fork latency spikes and EBS as a failure mode. Common for L1 caches fronting RDS/DynamoDB.

## Cluster scaling limits

> "The cluster's key space is split into 16384 slots, effectively setting an upper limit for the cluster size of 16384 primary nodes (however, the suggested max size of nodes is on the order of ~ 1000 nodes)."
> — [Valkey Cluster Specification](https://valkey.io/topics/cluster-spec/)

The ~1000-node guidance is a *gossip-protocol* limit, not a slot limit. AWS ElastiCache caps at 500 nodes per cluster (83–500 shards) for Valkey ≥ 5.0.6 — [docs](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/CacheNodes.NodeGroups.html). The Valkey project [demonstrated 2,000 nodes](https://valkey.io/blog/1-billion-rps/) (1000 shards × 1 replica) driving 1 billion RPS — beyond the recommended ceiling but possible.

Practical buckets (this chart):

| Bucket | Shards | Total pods (1 replica each) | Working set | What to watch | When to split |
|---|---|---|---|---|---|
| **Small** | 3–10 | 6–20 | < 100 GB | Trivial; default `cluster-node-timeout: 15s` is fine | Never on size |
| **Medium** | 10–50 | 20–100 | 100 GB – 1 TB | Client topology refresh storms — prefer clients that cache `CLUSTER SHARDS` | If RPS > 5M, consider tenant-split |
| **Large** | 50–200 | 100–400 | 1–5 TB | Gossip CPU; raise `cluster-node-timeout` to 30s; legacy reshard slow (~30–60 s/GB) | If a single reshard > 1 hr, multi-cluster |
| **Very large** | 200–500 | 400–1000 | 5–25 TB | Approaching gossip ceiling; rolling upgrade ≈ pods × 90s ≈ several hours; ENI / IP plan critical | **Shard at the application layer** |
| **Beyond** | > 500 | > 1000 | > 25 TB | Officially "unsupported scale"; only proven by valkey.io benchmark teams | Always split |

### What gets harder at scale

- **Gossip CPU.** Each PING/PONG payload gossips a random subset of node metadata. At 500 nodes that's ~1–5% steady CPU per pod. At 1000+ nodes, expect 5–15%.
- **`CLUSTER NODES` size.** ~150 bytes per node. 1000 nodes = 150 KB response. Every client that issues `CLUSTER NODES` (vs `CLUSTER SHARDS`) eats this on startup. Use `CLUSTER SHARDS` clients (jedis 4.4+, lettuce 6.2+, go-redis v9, redis-py 5+).
- **Rolling upgrade time.** PDB `maxUnavailable: 1` means serial pod restarts. At ~90s per restart, 100 pods = 2.5 hours, 500 pods = 12+ hours. Plan maintenance windows accordingly.
- **Slot resharding.** Valkey 7.2/8.0 uses key-by-key `MIGRATE`, ~30–60 seconds per GB per slot range. Atomic Slot Migration (ASM) in newer engines is ~100× faster but not yet in stable Valkey.

If any of these become operationally painful, **shard at the application layer** into multiple smaller Valkey clusters rather than scaling a single cluster past ~200 shards.

## Deployment

The chart deploys alongside the replication-mode default in a separate namespace (`valkey-cluster`).

### Prerequisites

- Data-on-eks Valkey stack already deployed (the Valkey NodePool, the `gp3` StorageClass, ArgoCD, and the existing replication-mode release are all expected).
- `helm` 3.13+ and `kubectl` configured for the EKS cluster.
- (Recommended for production-grade I/O) the `valkey-gp3` StorageClass applied — see [storage section](#choosing-storage).

### Quickstart

```bash
cd data-stacks/valkey-on-eks/examples
./install-cluster-mode.sh                              # default: 6 pods, ns=valkey-cluster
./install-cluster-mode.sh --replicas 9 \
   --replicas-per-primary 2                            # 3 primaries × 2 replicas each
./install-cluster-mode.sh --values my-values.yaml      # custom overrides
./install-cluster-mode.sh --dry-run                    # render templates only
```

The script wraps `helm install/upgrade` with the right defaults. To uninstall:

```bash
./uninstall-cluster-mode.sh           # keeps PVCs and the auth Secret
./uninstall-cluster-mode.sh --purge   # delete everything
```

### What the chart deploys

| Resource | Purpose |
|---|---|
| `StatefulSet/valkey-cluster` | 6 pods (`podManagementPolicy: Parallel`), kernel-tuning init container, prepare-config init container, valkey + metrics containers |
| `Service/valkey-cluster-headless` | Headless service (`clusterIP: None`, `publishNotReadyAddresses: true`) — per-pod DNS + cluster bus discovery |
| `Secret/valkey-cluster-auth` | Auto-generated 32-char password; preserved across `helm upgrade` via `lookup` |
| `ConfigMap/valkey-cluster-config` | `valkey.conf` — cluster mode + persistence + the include for `/data/conf/auth.conf` |
| `ConfigMap/valkey-cluster-scripts` | `topology.sh`, `bootstrap.sh`, `readiness.sh`, `prestop.sh` |
| `Job/valkey-cluster-bootstrap` | Post-install / post-upgrade Hook — runs `valkey-cli --cluster create` once; idempotent on re-runs |
| `Role`, `RoleBinding`, `ClusterRole`, `ClusterRoleBinding` | Minimal RBAC for the bootstrap Job's kubectl init container (pod list, node read) |
| `ServiceAccount/valkey-cluster` | Pod identity (no IAM yet; reserved for future restore-from-S3) |
| `PodDisruptionBudget` | `maxUnavailable: 1` |
| `ServiceMonitor` | Prometheus scrape config for the redis_exporter sidecar |
| `NetworkPolicy` (opt-in) | Default-deny + explicit allow for intra-cluster, application namespaces, and Prometheus scrape |

### AZ-aware bootstrap (default ON)

The post-install Hook Job runs a `topology.sh` init container with kubectl that maps each pod to its node's `topology.kubernetes.io/zone` label. The main bootstrap container reads this map and pairs each replica with a primary **in a different AZ**, so any single-AZ outage can be survived by failover. Without this, `valkey-cli --cluster create --cluster-replicas N` would pair by hostname pattern only — which, for a single StatefulSet, often produces same-AZ pairs and defeats the HA guarantee.

To disable (single-AZ dev environments):

```yaml
topology:
  azAwareBootstrap: false
```

### Verifying the install

```bash
PASS=$(kubectl -n valkey-cluster get secret valkey-cluster-auth \
        -o jsonpath='{.data.default}' | base64 -d)

# Cluster info — expect all six lines
kubectl -n valkey-cluster exec valkey-cluster-0 -c valkey -- \
  valkey-cli -a "$PASS" --no-auth-warning cluster info | head -6
# cluster_state:ok
# cluster_slots_assigned:16384
# cluster_slots_ok:16384
# cluster_slots_pfail:0
# cluster_slots_fail:0
# cluster_known_nodes:6

# Topology
kubectl -n valkey-cluster exec valkey-cluster-0 -c valkey -- \
  valkey-cli -a "$PASS" --no-auth-warning cluster shards
```

Then run a smoke test:

```bash
# Cluster-aware writes/reads
kubectl -n valkey-cluster exec -i valkey-cluster-0 -c valkey -- \
  valkey-cli -c -a "$PASS" --no-auth-warning <<'CMD'
SET test:user:42 alice
SET test:order:9001 "$50"
GET test:user:42
GET test:order:9001
CMD

# Quick benchmark
kubectl -n valkey-cluster exec valkey-cluster-0 -c valkey -- \
  valkey-benchmark -a "$PASS" --cluster \
    -h valkey-cluster-0.valkey-cluster-headless.valkey-cluster.svc.cluster.local \
    -p 6379 -t set,get -n 10000 -c 50 -q
```

## Connecting clients

Cluster mode requires a **cluster-aware client**.

| Library | Cluster-aware client class |
|---|---|
| `redis-py` ≥ 4.1 | `redis.cluster.RedisCluster` |
| Lettuce (Java) | `RedisClusterClient` |
| Jedis | `JedisCluster` |
| ioredis | `Redis.Cluster` |
| `go-redis` | `redis.NewClusterClient` |
| valkey-glide | native cluster mode support |

Connect via the headless service:

```python
from redis.cluster import RedisCluster, ClusterNode

nodes = [
    ClusterNode(f"valkey-cluster-{i}.valkey-cluster-headless.valkey-cluster.svc.cluster.local", 6379)
    for i in range(6)
]
client = RedisCluster(
    startup_nodes=nodes,
    password=os.environ["VALKEY_PASSWORD"],
    decode_responses=True,
)
client.set("user:42:profile", "carol@example.com")
client.get("user:42:profile")
```

The cluster client calls `CLUSTER SHARDS` once at startup to learn the slot map, then routes commands directly to the owning primary. Writes go to primaries; default reads also go to primaries. To load-balance reads across replicas, call `READONLY` on the connection after open — most cluster clients expose a `read_from_replicas=True` flag for this.

## Best practices

### Authentication

The chart enables auth by default with `requirepass` + `primaryauth` sharing the same auto-generated 32-char password from a Kubernetes Secret. The Secret is preserved across `helm upgrade` via a `lookup` guard — running upgrade does NOT rotate the password (which would break the cluster, because running pods cache the password in env at startup).

To use your own externally-managed Secret:

```yaml
auth:
  enabled: true
  existingSecret: my-valkey-secret      # must contain key `default`
  existingSecretPasswordKey: default
```

The chart deliberately does NOT use an ACL file. It would add a separate `replication-user` ACL that needs `+psync +replconf +ping` (and **not** the non-existent `+@replication` category — a common copy-paste trap). `requirepass` + `primaryauth` is simpler and matches the [Microsoft AKS reference](https://learn.microsoft.com/en-us/azure/aks/deploy-valkey-cluster) for Valkey cluster mode.

### Strict AZ spread

Default:

```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app.kubernetes.io/name: valkey-cluster
```

`DoNotSchedule` is critical — `ScheduleAnyway` lets two pods land in the same AZ, and combined with the AZ-aware bootstrap puts you in a state where one AZ has no replica. For dev/test in single-AZ clusters, switch to `ScheduleAnyway`.

### Persistence (required for cluster mode)

```ini
appendonly yes
appendfsync everysec
save 900 1
save 300 10
save 60 10000
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb
```

Without persistence, a pod restart restores an empty dataset. The replica resyncs via PSYNC from the primary — fine in steady state, but during a controlled rolling restart of the *entire* cluster (e.g., AMI bump), the first pod back up must have its data on disk or that shard's keyspace is gone.

### Kernel tuning (Transparent Huge Pages)

Valkey [docs require](https://valkey.io/topics/admin/) THP disabled:

> "echo never > /sys/kernel/mm/transparent_hugepage/enabled"

With THP enabled, a single-byte write by the BGSAVE parent copies a 2 MB page — ~500× write amplification. The chart's `kernel-tuning` init container handles this with a privileged container that runs as root for ~1 second:

```yaml
kernelTuning:
  enabled: true        # default
```

It also sets `net.core.somaxconn=65535` and `vm.overcommit_memory=1`.

If your namespace has the [restricted PSA profile](https://kubernetes.io/docs/concepts/security/pod-security-standards/) set, this container will be rejected. Two options:

1. Apply the same tuning at the node level via a separate DaemonSet that runs once at boot, then set `kernelTuning.enabled: false`.
2. Move Valkey to a namespace with `baseline` or no PSA enforcement.

### PodDisruptionBudget — `maxUnavailable: 1`

```yaml
pdb:
  enabled: true
  maxUnavailable: 1
```

Cluster mode tolerates **one primary down** because failover requires a majority of the remaining 2 primaries to agree (2/3 = quorum). `maxUnavailable: 2` could remove 2 primaries simultaneously and stall failover.

For deeper safety during voluntary disruptions (node drains, Karpenter consolidation), pair the PDB with `pod-deletion-cost` annotations to bias eviction toward replicas first.

### Network policy

Off by default in the chart. Turn on once you know which application namespaces need port 6379:

```yaml
networkPolicy:
  enabled: true
  allowedFrom:
    - matchLabels:
        role: app
    - matchLabels:
        team: ml-platform
```

Intra-cluster traffic on 6379 + 16379 is always allowed (every Valkey pod talks to every other). DNS egress to kube-dns is allowed. Prometheus is permitted on `:9121`.

## How failover works

Failover happens in two flavors: **unplanned** (a pod or node dies) and **planned** (you want to rotate the primary role, e.g., for a node upgrade).

### Unplanned (automatic, gossip-driven)

```
T+0s    Primary pod-0 dies (kernel panic, AZ outage, OOM-kill)
T+0-15s Pod-3 (the replica) keeps trying to send REPLCONF heartbeats — no response
T+15s   `cluster-node-timeout` expires. Pod-3 marks pod-0 as PFAIL and gossips it.
T+15-30s Pods 1, 2, 4, 5 receive the PFAIL gossip. Each compares against their own
        view. When the majority of primaries (pod-1 and pod-2) agree, pod-0 is FAIL.
T+30-45s Pod-3 starts a failover election: it broadcasts a FAILOVER_AUTH_REQUEST to
        all primaries. Each primary checks its `lastVoteEpoch` and votes once per
        epoch. If pod-3 receives majority votes (>1 of 2 remaining primaries), it
        promotes.
T+45s   Pod-3 issues `CLUSTER FAILOVER TAKEOVER` and bumps its config epoch. Its
        slot range (0-5460) is now owned by pod-3 across the gossip table.
T+45-60s Existing client connections hit `MOVED 5403 pod-3:6379` on the next command
        for that slot range. Clients update their slot map. Writes resume.
```

End-to-end, expect **30–60 seconds of write unavailability** for the affected shard in the default `cluster-node-timeout: 15s` configuration. Reads continue to the replica (now primary) once promoted.

To tune: lower `cluster-node-timeout` for faster detection (cost: higher gossip rate, more false positives under transient network blips). Don't go below 5s on multi-AZ deployments.

### Planned (graceful, via CLUSTER FAILOVER)

Use this to rotate the primary role onto a specific replica — e.g., before a node upgrade or to rebalance load.

```bash
PASS=$(kubectl -n valkey-cluster get secret valkey-cluster-auth -o jsonpath='{.data.default}' | base64 -d)

# Find the replica you want to promote (e.g., valkey-cluster-3 replicates valkey-cluster-0)
kubectl -n valkey-cluster exec valkey-cluster-3 -c valkey -- \
  valkey-cli -a "$PASS" --no-auth-warning cluster failover

# Verify
kubectl -n valkey-cluster exec valkey-cluster-3 -c valkey -- \
  valkey-cli -a "$PASS" --no-auth-warning role | head -1
# master
```

`CLUSTER FAILOVER` (without `FORCE` or `TAKEOVER`) coordinates with the primary: the replica catches up to the primary's offset, then both swap roles atomically. The window where writes can't proceed is **typically < 1 second** — much faster than the unplanned 30-60s.

The chart's `preStop` hook (`/scripts/prestop.sh`) does exactly this when a pod is being terminated: if the pod is currently a primary, it picks a healthy replica and runs `CLUSTER FAILOVER`, waits up to 10s for the role swap, then `SHUTDOWN`. This is what makes the rolling upgrade smooth — see the next section.

### When failover stalls

`cluster_state:fail` after a multi-pod outage means the cluster lost quorum. Recovery:

```bash
PASS=$(kubectl -n valkey-cluster get secret valkey-cluster-auth -o jsonpath='{.data.default}' | base64 -d)

# 1. Wait for failed pods to come back. The chart's prepare-config init container
#    rewrites /data/conf/auth.conf and the bootstrap.sh in the StatefulSet's
#    main container restarts. Each pod loads its previous nodes.conf from PVC
#    and rejoins via gossip — no manual MEET needed.
kubectl -n valkey-cluster get pods

# 2. If pods rejoin but the cluster stays in fail state, identify the surviving
#    primaries and check their voting state:
for i in 0 1 2 3 4 5; do
  kubectl -n valkey-cluster exec valkey-cluster-$i -c valkey -- \
    valkey-cli -a "$PASS" --no-auth-warning cluster info | grep cluster_state
done

# 3. As a last resort, force a slot takeover on a surviving primary that owns
#    the orphaned slot range:
kubectl -n valkey-cluster exec valkey-cluster-0 -c valkey -- \
  valkey-cli -a "$PASS" --no-auth-warning cluster failover takeover
```

`FAILOVER TAKEOVER` skips the consensus wait — only use when you've confirmed the original primary is permanently lost. If `nodes.conf` is corrupted across multiple PVCs simultaneously (rare; would require multiple PVC failures), the only path is **restore from RDB backup** per shard via the [EC2 → EKS migration runbook](./ec2-migration.md).

## Planned upgrades

Three independent upgrade dimensions — handle them one at a time. The cluster's `cluster_state` should stay `:ok` throughout each one.

### Pre-flight checklist

```bash
PASS=$(kubectl -n valkey-cluster get secret valkey-cluster-auth -o jsonpath='{.data.default}' | base64 -d)

# 1. All 6 pods 2/2 Ready
kubectl -n valkey-cluster get pods

# 2. cluster_state:ok, all 16384 slots covered
kubectl -n valkey-cluster exec valkey-cluster-0 -c valkey -- \
  valkey-cli -a "$PASS" --no-auth-warning cluster info | head -6

# 3. Replication healthy on every replica
for i in 3 4 5; do
  kubectl -n valkey-cluster exec valkey-cluster-$i -c valkey -- \
    valkey-cli -a "$PASS" --no-auth-warning info replication | grep -E '^(role|master_link_status):'
done

# 4. PDB allows 1 disruption
kubectl -n valkey-cluster get pdb valkey-cluster
# expect: maxUnavailable=1, disruptionsAllowed=1
```

If any pre-flight fails, fix before upgrading.

### Chart bump (config-only)

For chart changes that don't touch the StatefulSet's pod template (e.g., a new ServiceMonitor label, a NetworkPolicy tweak):

```bash
helm upgrade valkey-cluster ./cluster-mode-helm-chart -n valkey-cluster
```

No pod restart. The post-upgrade Hook Job runs `bootstrap.sh`, sees `cluster_state:ok` already, and exits 0.

### Valkey image version bump

For the underlying Valkey container image (e.g., 9.0.2 → 9.0.3):

```yaml
# overrides.yaml
image:
  tag: "9.0.3"
```

```bash
helm upgrade valkey-cluster ./cluster-mode-helm-chart -n valkey-cluster -f overrides.yaml
```

The StatefulSet's pod template changes → rolling restart in **reverse-ordinal order** (pod 5 → 4 → 3 → 2 → 1 → 0), one pod at a time (enforced by PDB `maxUnavailable: 1`). For each pod:

1. K8s sends SIGTERM. `preStop` runs.
2. If the pod is a **primary**, `prestop.sh` issues `CLUSTER FAILOVER` to its replica. The replica's role flips to primary within ~1 second; clients see at most one `MOVED` redirect.
3. `SHUTDOWN` is sent; the server flushes AOF and exits.
4. Pod re-creates with the new image, runs the init containers (kernel tuning + prepare-config), then the main container.
5. New container starts — the existing `/data/nodes.conf` carries this pod's node ID. The cluster's other 5 pods recognize it via gossip.
6. Readiness probe waits for `cluster_state:ok` + `cluster_slots_assigned:16384`.
7. PDB releases — next pod can roll.

End-to-end for 6 pods at ~90s per pod: ~10 minutes. Tested in the chart development with sustained writes — 97% write success during the upgrade window, with the 3% gap landing in the seconds when the last primary (pod 0) failed over to its replica.

After upgrade, the master/replica roles are typically **flipped** vs the start (every primary's `preStop` triggers a failover to its replica). This is intentional and harmless; you can flip them back later via `CLUSTER FAILOVER` if you want a stable mapping for monitoring dashboards.

### Karpenter AMI rollover

When the Karpenter NodePool's underlying AMI bumps (e.g., AL2023 security patch), the existing nodes drift and get replaced. Karpenter respects PDBs, so the cluster mode rollover behaves exactly like the image bump above — one pod evicted at a time, `preStop` does graceful failover, replica catches up before next pod.

To control timing:

```bash
# Disable Karpenter's automatic drift correction temporarily
kubectl -n karpenter patch nodepool valkey --type merge -p \
  '{"spec":{"disruption":{"budgets":[{"nodes":"0"}]}}}'

# … manually drain when ready …
kubectl drain ip-100-64-xxx --ignore-daemonsets --delete-emptydir-data

# Re-enable
kubectl -n karpenter patch nodepool valkey --type merge -p \
  '{"spec":{"disruption":{"budgets":[{"nodes":"1"}]}}}'
```

### Rolling upgrade test (verification)

Before relying on the upgrade path in production, exercise it once with sustained traffic. A pattern that worked during chart development:

```bash
PASS=$(kubectl -n valkey-cluster get secret valkey-cluster-auth -o jsonpath='{.data.default}' | base64 -d)

# Terminal A — sustained workload
for i in $(seq 1 600); do
  kubectl -n valkey-cluster exec valkey-cluster-0 -c valkey -- \
    valkey-cli -c -a "$PASS" --no-auth-warning SET "upgrade:probe:$i" "v" \
    && echo "$(date +%T) ok" || echo "$(date +%T) FAIL"
  sleep 0.5
done > /tmp/probe.log &

# Terminal B — monitor cluster health
while true; do
  kubectl -n valkey-cluster exec valkey-cluster-0 -c valkey -- \
    valkey-cli -a "$PASS" --no-auth-warning cluster info | grep cluster_state
  sleep 2
done

# Terminal C — trigger the upgrade
helm upgrade valkey-cluster ./cluster-mode-helm-chart -n valkey-cluster -f overrides.yaml

# After completion
grep -c FAIL /tmp/probe.log
# expect < 5% — failures concentrate at the moment the last primary fails over
```

## Operational runbooks

### Scale out (add a shard)

Cluster mode scales by adding shards (a primary + its replica), not by adding pods to existing shards. The chart's bootstrap is one-shot — for scale-out, follow this manual procedure:

```bash
PASS=$(kubectl -n valkey-cluster get secret valkey-cluster-auth -o jsonpath='{.data.default}' | base64 -d)

# 1. Scale the StatefulSet
kubectl -n valkey-cluster scale statefulset valkey-cluster --replicas=8

# 2. Wait for pods 6 and 7 to be Running (they'll be in "bootstrap-pending"
#    Readiness state — that's expected, they haven't been joined yet)
kubectl -n valkey-cluster get pods

# 3. Add pod 6 as a new primary
kubectl -n valkey-cluster exec valkey-cluster-0 -c valkey -- \
  valkey-cli -a "$PASS" --no-auth-warning --cluster add-node \
    valkey-cluster-6.valkey-cluster-headless.valkey-cluster.svc.cluster.local:6379 \
    valkey-cluster-0.valkey-cluster-headless.valkey-cluster.svc.cluster.local:6379

# 4. Reshard — move ~4096 slots from existing primaries to pod 6
NEW_PRIMARY_ID=$(kubectl -n valkey-cluster exec valkey-cluster-6 -c valkey -- \
  valkey-cli -a "$PASS" --no-auth-warning cluster myid)

kubectl -n valkey-cluster exec valkey-cluster-0 -c valkey -- \
  valkey-cli -a "$PASS" --no-auth-warning --cluster reshard \
    valkey-cluster-0.valkey-cluster-headless.valkey-cluster.svc.cluster.local:6379 \
    --cluster-from all --cluster-to "$NEW_PRIMARY_ID" \
    --cluster-slots 4096 --cluster-yes

# 5. Add pod 7 as a replica of pod 6, in a different AZ if possible
kubectl -n valkey-cluster exec valkey-cluster-0 -c valkey -- \
  valkey-cli -a "$PASS" --no-auth-warning --cluster add-node \
    valkey-cluster-7.valkey-cluster-headless.valkey-cluster.svc.cluster.local:6379 \
    valkey-cluster-0.valkey-cluster-headless.valkey-cluster.svc.cluster.local:6379 \
    --cluster-slave --cluster-master-id "$NEW_PRIMARY_ID"
```

Resharding is **online** — clients see brief `MOVED` / `ASK` redirects but no errors. Budget **30–60 seconds per GB** of resharded data on legacy migration.

### Scale in (remove a shard)

```bash
# 1. Drain slots off the shard being removed (move them to another primary)
DRAIN_ID=$(kubectl -n valkey-cluster exec valkey-cluster-6 -c valkey -- \
  valkey-cli -a "$PASS" --no-auth-warning cluster myid)
DEST_ID=$(kubectl -n valkey-cluster exec valkey-cluster-0 -c valkey -- \
  valkey-cli -a "$PASS" --no-auth-warning cluster myid)

kubectl -n valkey-cluster exec valkey-cluster-0 -c valkey -- \
  valkey-cli -a "$PASS" --no-auth-warning --cluster reshard \
    valkey-cluster-0.valkey-cluster-headless.valkey-cluster.svc.cluster.local:6379 \
    --cluster-from "$DRAIN_ID" --cluster-to "$DEST_ID" \
    --cluster-slots 16384 --cluster-yes

# 2. Remove pod 6 and 7 from the cluster
for ID in $DRAIN_ID $REPLICA_ID; do
  kubectl -n valkey-cluster exec valkey-cluster-0 -c valkey -- \
    valkey-cli -a "$PASS" --no-auth-warning --cluster del-node \
      valkey-cluster-0.valkey-cluster-headless.valkey-cluster.svc.cluster.local:6379 \
      "$ID"
done

# 3. Scale the StatefulSet down
kubectl -n valkey-cluster scale statefulset valkey-cluster --replicas=6

# 4. Clean up the orphaned PVCs (StatefulSet doesn't auto-delete them)
kubectl -n valkey-cluster delete pvc data-valkey-cluster-6 data-valkey-cluster-7
```

### Recover from a wedged bootstrap

If the post-install Hook Job fails (e.g., a pod is stuck restarting), the Job stays in `Failed` state for debugging (the chart uses `hook-delete-policy: before-hook-creation,hook-succeeded`).

```bash
# Inspect logs
kubectl -n valkey-cluster logs -l app.kubernetes.io/component=bootstrap -c topology
kubectl -n valkey-cluster logs -l app.kubernetes.io/component=bootstrap -c bootstrap

# Fix the underlying issue (config error, image pull, etc.), then re-run helm
kubectl -n valkey-cluster delete job valkey-cluster-bootstrap
helm upgrade valkey-cluster ./cluster-mode-helm-chart -n valkey-cluster
```

`bootstrap.sh` is idempotent — if `cluster_state:ok` already, it exits 0 without re-running `--cluster create`.

### Reset everything (dev / test)

```bash
./uninstall-cluster-mode.sh --purge     # removes PVCs + Secret + namespace
./install-cluster-mode.sh               # fresh install
```

## Migration from Replication Mode

Already running this stack's replication mode and want to migrate to cluster mode without downtime?

1. Deploy the cluster-mode chart in the `valkey-cluster` namespace (the default). Both releases run in parallel.
2. Use `valkey-cli --cluster import` from a temporary client pod to live-migrate keys:

   ```bash
   kubectl -n valkey-cluster run valkey-migrate --rm -it \
     --image=docker.io/valkey/valkey:9.0.2 --restart=Never -- /bin/sh

   # Inside the pod:
   valkey-cli --cluster import \
     valkey-cluster-0.valkey-cluster-headless.valkey-cluster.svc.cluster.local:6379 \
     --cluster-from valkey.valkey.svc.cluster.local:6379 \
     --cluster-from-pass "$REPLICATION_PASS" \
     --cluster-from-user default \
     --cluster-replace
   ```

3. Cut application traffic over to the cluster-mode endpoints (cluster-aware client library required).
4. Once stable, decommission the replication-mode release.

`--cluster import` uses `DUMP` / `RESTORE` for live key migration. Expect ~5–20 MB/s per source connection; parallelize by hash-slot range for very large datasets.

## References

- [Valkey Cluster Specification](https://valkey.io/topics/cluster-spec/) — protocol-level reference for slot assignment, gossip, failover.
- [Valkey Cluster Tutorial](https://valkey.io/topics/cluster-tutorial/) — hands-on companion to the spec.
- [Valkey Administration Docs](https://valkey.io/topics/admin/) — THP, fork tuning, kernel guidance.
- [Valkey 1B RPS benchmark](https://valkey.io/blog/1-billion-rps/) — scale ceiling demo (1000 shards).
- [Microsoft AKS Valkey Cluster reference](https://learn.microsoft.com/en-us/azure/aks/deploy-valkey-cluster) — the architectural pattern this chart adopts.
- [valkey-helm PR #51](https://github.com/valkey-io/valkey-helm/pull/51) — the upstream PR being tracked for native cluster support.
- [valkey-helm #18](https://github.com/valkey-io/valkey-helm/issues/18) — official cluster-mode roadmap.
- [AWS ElastiCache supported node types](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/CacheNodes.SupportedTypes.html) — current instance families AWS recommends.
- [AWS gp3 EBS docs](https://docs.aws.amazon.com/ebs/latest/userguide/general-purpose.html) — IOPS/throughput knobs and pricing.
- [AWS VPC CNI Prefix Delegation](https://docs.aws.amazon.com/eks/latest/userguide/cni-increase-ip-addresses.html) — pod-density planning.
