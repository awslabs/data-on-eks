---
title: Cluster Mode (Self-Managed Manifests)
sidebar_position: 5
---

# Cluster Mode — Self-Managed Manifests

Valkey Cluster (sharded with hash-slot partitioning and gossip-based failover) is **not yet supported by the official `valkey-io/valkey-helm` chart** — see [valkey-helm #18](https://github.com/valkey-io/valkey-helm/issues/18) for the roadmap. Until upstream cluster support ships, this stack provides Cluster mode as **plain Kubernetes manifests** (no Helm chart, no operator).

The design draws directly from [valkey-helm PR #51](https://github.com/valkey-io/valkey-helm/pull/51) ("Add cluster mode support" by `qjsoq`), which is the most credible open implementation of the manifest pattern. When PR #51 (or its successor) merges, this doc will be reduced to a thin overlay on the official chart.

This guide covers:

1. The manifest topology and why each piece is shaped the way it is.
2. The bootstrap script — how the cluster forms on first boot, and how pods rejoin after restart without operator intervention.
3. Production best practices: AZ spread, persistent storage, security, scaling.
4. Operational runbooks: scaling out, scaling replicas per shard, recovering from quorum loss.

## When to Use Cluster Mode

Use Cluster mode when at least one of these holds:

- **Working set > single node memory.** Your data exceeds what a single `r7g.16xlarge` (~512 GiB) can hold, or you want to keep per-node memory pressure down for fork-time CoW headroom on snapshots.
- **Write throughput > single primary.** Replication mode has one primary; all writes serialize through it. Cluster mode shards writes across N primaries, scaling write throughput linearly with shard count (subject to cross-slot constraints).
- **Multi-key operations are NOT a hard requirement.** Cluster mode rejects multi-key commands (`MGET`, `MSET`, `RENAME`, `SUNIONSTORE`, transactions, Lua scripts) when the keys span different hash slots — the application must use [hash tags](https://valkey.io/topics/cluster-spec/#hash-tags) (`{user:1}:profile` and `{user:1}:settings` hash to the same slot) or accept per-key operations only.

If your dataset fits a single large-memory node and your workload is read-heavy, **stay on replication mode**. Cluster mode adds operational complexity that's only worth it for scale.

| Factor | Replication Mode | Cluster Mode |
|---|---|---|
| Topology | 1 primary + N replicas | 3+ primaries × 1+ replica each (minimum 6 pods) |
| Write scaling | ✗ — single primary | ✓ — sharded across primaries by hash slot |
| Multi-key ops | ✓ — single keyspace | Same-slot only (use hash tags) |
| Failover | Manual `REPLICAOF NO ONE` | Automatic (gossip-based, ~10s to detect + promote) |
| Min nodes (HA) | 2 (1 primary + 1 replica) | 6 (3 primaries + 3 replicas) for full HA |
| Operational surface | Lower | Higher (gossip, slot rebalancing, MEET/FORGET) |
| Chart support | ✓ Official `valkey-io/valkey-helm` | Self-managed manifests until [#18](https://github.com/valkey-io/valkey-helm/issues/18) lands |

## Architecture

```
┌─────────────────────────── EKS Cluster ────────────────────────────┐
│                                                                    │
│  AZ us-west-2a            AZ us-west-2b           AZ us-west-2c    │
│  ┌──────────────┐         ┌──────────────┐        ┌──────────────┐ │
│  │ valkey-c-0   │ ◄──┐    │ valkey-c-1   │ ◄──┐   │ valkey-c-2   │ │
│  │ primary      │    │    │ primary      │    │   │ primary      │ │
│  │ slots 0-5460 │    │    │ slots 5461-  │    │   │ slots 10923- │ │
│  │              │    │    │       10922  │    │   │       16383  │ │
│  └──────────────┘    │    └──────────────┘    │   └──────────────┘ │
│                      │                        │                    │
│  ┌──────────────┐    │    ┌──────────────┐    │   ┌──────────────┐ │
│  │ valkey-c-3   │ ◄──┘    │ valkey-c-4   │ ◄──┘   │ valkey-c-5   │ │
│  │ replica of   │         │ replica of   │        │ replica of   │ │
│  │ valkey-c-0   │         │ valkey-c-1   │        │ valkey-c-2   │ │
│  └──────────────┘         └──────────────┘        └──────────────┘ │
│                                                                    │
│  Cross-AZ async replication (TCP 6379)                             │
│  Cluster bus gossip       (TCP 16379) — full mesh between all 6   │
│                                                                    │
│  Service `valkey-cluster-headless` (ClusterIP: None)               │
│   ├─ valkey-c-0.valkey-cluster-headless.<ns>.svc.cluster.local     │
│   ├─ valkey-c-1...                                                 │
│   └─ valkey-c-5...    (per-pod stable DNS)                         │
└────────────────────────────────────────────────────────────────────┘
```

### Topology rules

- **Minimum 6 pods**: 3 primaries (for split-brain quorum during failover) × 1 replica each. The cluster spec mandates that a primary failure is only failed-over if **the majority of remaining primaries** agree — with 2 primaries, a single primary failure leaves 1 voter, no quorum, no failover.
- **AZ spread**: each primary in a different AZ. Each replica in a different AZ than its primary. Survives a single-AZ outage with no data loss and automatic failover.
- **Per-pod PVC**: `volumeClaimTemplates` create one PVC per StatefulSet ordinal. Each PVC is AZ-pinned via the gp3 StorageClass (`volumeBindingMode: WaitForFirstConsumer`).
- **Stable identity**: each pod gets a stable DNS name via the headless Service. The cluster's gossip table references hostnames (where supported by the client) so pod-IP changes after restart are absorbed by CoreDNS.

## Manifests

The full manifest set lives at `data-stacks/valkey-on-eks/examples/cluster-mode/` (provisioned in a follow-up patch — see the [Roll Your Own](#roll-your-own) section below to write them directly). The pieces:

| File | Purpose |
|---|---|
| `namespace.yaml` | Dedicated `valkey-cluster` namespace |
| `secret.yaml` | ACL passwords (`default` + `replication-user`) |
| `configmap-config.yaml` | `valkey.conf` — cluster mode + ACL + persistence config |
| `configmap-scripts.yaml` | The `init-cluster.sh` and readiness/preStop scripts |
| `serviceaccount.yaml` | Pod ServiceAccount (for future Pod Identity hooks) |
| `service-headless.yaml` | Headless Service (ClusterIP: None) on `:6379` and `:16379` |
| `service-client.yaml` | Optional ClusterIP Service for clients that don't need per-pod DNS |
| `pdb.yaml` | PodDisruptionBudget — `maxUnavailable: 1` |
| `networkpolicy.yaml` | Allow cluster bus + intra-namespace traffic |
| `statefulset.yaml` | The 6-pod StatefulSet with init container, sidecar bootstrapper, preStop hook |

### StatefulSet — the central piece

Annotated essentials (full manifest in the example directory):

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: valkey-cluster
  namespace: valkey-cluster
spec:
  serviceName: valkey-cluster-headless     # Required for per-pod DNS
  replicas: 6                              # 3 primaries × 1 replica = 6 pods
  podManagementPolicy: OrderedReady        # Deterministic bootstrap order
  selector:
    matchLabels:
      app.kubernetes.io/name: valkey-cluster
  template:
    metadata:
      labels:
        app.kubernetes.io/name: valkey-cluster
    spec:
      terminationGracePeriodSeconds: 60    # Time for preStop CLUSTER FAILOVER + FORGET
      nodeSelector:
        NodeGroupType: valkey
      tolerations:
        - key: workload
          operator: Equal
          value: valkey
          effect: NoSchedule
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchLabels:
              app.kubernetes.io/name: valkey-cluster
      containers:
        - name: valkey
          image: docker.io/valkey/valkey:9.0.2
          command: ["/bin/sh", "-c"]
          args:
            - |
              # Background: kick off the cluster bootstrap/rejoin coordinator
              /scripts/init-cluster.sh &
              # Foreground: start the Valkey server (the script will issue
              # CLUSTER MEET / CLUSTER REPLICATE against this server once it pings)
              exec valkey-server /etc/valkey/valkey.conf
          env:
            - name: HOSTNAME
              valueFrom: { fieldRef: { fieldPath: metadata.name } }
            - name: NAMESPACE
              valueFrom: { fieldRef: { fieldPath: metadata.namespace } }
            - name: POD_IP
              valueFrom: { fieldRef: { fieldPath: status.podIP } }
            - name: REPLICAS
              value: "6"
            - name: HEADLESS_SVC
              value: "valkey-cluster-headless"
            - name: VALKEYCLI_AUTH
              valueFrom:
                secretKeyRef:
                  name: valkey-cluster-auth
                  key: default
          ports:
            - { name: tcp, containerPort: 6379 }
            - { name: bus, containerPort: 16379 }
          volumeMounts:
            - { name: data, mountPath: /data }
            - { name: config, mountPath: /etc/valkey/valkey.conf, subPath: valkey.conf }
            - { name: scripts, mountPath: /scripts }
          readinessProbe:
            exec:
              command: ["/scripts/readiness.sh"]
            initialDelaySeconds: 15
            periodSeconds: 5
            timeoutSeconds: 6
            failureThreshold: 10
          livenessProbe:
            exec:
              command: ["valkey-cli", "ping"]
            periodSeconds: 5
            timeoutSeconds: 3
          lifecycle:
            preStop:
              exec:
                command: ["/scripts/prestop.sh"]
          resources:
            requests:
              cpu: "1000m"
              memory: "12Gi"      # ~70-80% of node RAM
            limits:
              memory: "16Gi"      # set == requests to avoid CoW OOM during BGSAVE
        - name: metrics
          image: oliver006/redis_exporter:v1.79.0
          env:
            - { name: REDIS_EXPORTER_IS_CLUSTER, value: "true" }
            - { name: REDIS_ADDR, value: "redis://127.0.0.1:6379" }
            - name: REDIS_PASSWORD
              valueFrom:
                secretKeyRef: { name: valkey-cluster-auth, key: default }
          ports:
            - { name: http-metrics, containerPort: 9121 }
      volumes:
        - name: config
          configMap: { name: valkey-cluster-config }
        - name: scripts
          configMap: { name: valkey-cluster-scripts, defaultMode: 0555 }
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: gp3
        resources:
          requests:
            storage: 100Gi
```

### Headless Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: valkey-cluster-headless
  namespace: valkey-cluster
spec:
  type: ClusterIP
  clusterIP: None                  # Headless — DNS publishes per-pod records
  publishNotReadyAddresses: true   # Critical: bootstrap needs DNS during init
  selector:
    app.kubernetes.io/name: valkey-cluster
  ports:
    - { name: tcp, port: 6379, targetPort: tcp }
    - { name: bus, port: 16379, targetPort: bus }
```

`publishNotReadyAddresses: true` is essential. During first-boot bootstrap, `valkey-cli --cluster create` needs to PING all 6 nodes — but at that moment none of them are Ready yet (the init script runs concurrently with the Valkey server). Without this flag, CoreDNS doesn't publish A records for not-Ready pods, and the bootstrap stalls.

### `valkey.conf`

```ini
# Cluster mode
cluster-enabled yes
cluster-config-file /data/nodes.conf
cluster-node-timeout 15000
cluster-require-full-coverage no       # Tolerate partial slot loss during recovery
cluster-allow-reads-when-down no       # Reject reads when this node loses majority

# Hostname-aware (Valkey 7.2+)
cluster-preferred-endpoint-type hostname

# Persistence — both AOF and RDB for max durability
appendonly yes
appendfsync everysec
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb
save 900 1
save 300 10
save 60 10000

# Memory and eviction
maxmemory 12gb                         # Match container resources.requests.memory
maxmemory-policy noeviction            # Cluster mode: never evict, prefer write rejection

# ACL
aclfile /etc/valkey/users.acl

# Slow log + latency monitoring (operational visibility)
slowlog-log-slower-than 10000
latency-monitor-threshold 100
```

The matching ACL file lives in the auth Secret:

```
user default on >${VALKEY_DEFAULT_PASSWORD} ~* &* +@all -@dangerous
user replication-user on >${VALKEY_REPLICATION_PASSWORD} +psync +replconf +ping
user default off                       # Disable passwordless default
```

## Bootstrap and Rejoin Logic

The cleverest part of the manifest design is `init-cluster.sh`. It runs in the **same container** as Valkey itself (`init-cluster.sh & exec valkey-server`), so it can drive `valkey-cli` against `localhost:6379` once the server is up. Pseudocode:

```text
ORDINAL = parse from $HOSTNAME (e.g., valkey-cluster-3 → 3)
PRIMARIES = ceil(REPLICAS / 2)           # 6 / 2 = 3
REPLICA_COUNT = (REPLICAS - PRIMARIES) / PRIMARIES   # (6 - 3) / 3 = 1

wait_for_local_valkey_ping()             # PING localhost until PONG

# Look for any existing healthy peer (rejoin path)
healthy_peer = scan_peers_for_cluster_state_ok()

if healthy_peer:
    # === REJOIN PATH ===
    # Forget any stale `myIP:6379-as-failed` entry on the healthy peer
    if peer_sees_my_ip_as_failed():
        valkey-cli --cluster call $peer:6379 cluster forget $stale_id
        sleep 3
    # Meet the cluster
    valkey-cli -h localhost cluster meet $peer_ip 6379
    # Find an under-replicated primary that isn't us, and become its replica
    target = pick_master_with_fewest_replicas(exclude=my_node_id)
    if target:
        valkey-cli -h localhost cluster replicate $target
    else:
        # Empty master with no slots — request rebalance from peer
        wait_for_majority_consensus()
        valkey-cli --cluster rebalance $peer:6379 --cluster-use-empty-masters --cluster-yes
    exit 0

# === BOOTSTRAP PATH ===
if ORDINAL == 0:
    # Wait for all 6 peers to PING (they're all booting concurrently)
    nodes = []
    for i in 0..5:
        wait_for_ping(valkey-cluster-${i}.headless...:6379)
        nodes.append("valkey-cluster-${i}.headless...:6379")
    sleep 10                              # Settle CoreDNS
    yes | valkey-cli --cluster create $nodes --cluster-replicas 1
else:
    wait_for_pod_0_to_say_cluster_state_ok()
```

Key properties:

1. **Idempotent**: the rejoin path runs on every pod start. If the cluster is already healthy, the pod's `CLUSTER MEET` is a no-op (the peer already knows us); `CLUSTER REPLICATE` against the same primary is a no-op.
2. **No leader election**: ordinal 0 is the bootstrapper *only* on first boot when no healthy cluster exists. After the cluster is formed, ordinal 0 is no different from any other pod.
3. **Self-healing**: if all 6 pods restart simultaneously (e.g., AMI rollover), the first one back up that finds at least one peer Ready does the rejoin path. The on-disk `nodes.conf` (in the PVC) carries each pod's node ID across restarts, so cluster identity is preserved.
4. **Failed-self cleanup**: when a pod restarts with a fresh IP, peers may still hold `myOldIP:6379` in their gossip tables marked `fail`. The script issues `CLUSTER FORGET` against any healthy peer to clear that entry before issuing `CLUSTER MEET` from the new IP.

### Readiness probe — consensus-based

A pod is Ready only when **a majority of its peers see it as healthy**:

```sh
# /scripts/readiness.sh (simplified)
my_id=$(valkey-cli cluster myid)
peers=$(valkey-cli cluster nodes | grep -v myself | grep -v fail | awk '{print $2}' | cut -d@ -f1)
total=$(echo "$peers" | wc -w)
required=$(( total - 1 ))    # tolerate 1 peer disagreement
success=0
for peer in $peers; do
  if valkey-cli -h "${peer%:*}" -p "${peer##*:}" cluster nodes | grep "$my_id" | grep -q connected; then
    success=$(( success + 1 ))
  fi
done
[ "$success" -ge "$required" ] && exit 0 || exit 1
```

This prevents the Service from sending traffic to a pod that's locally healthy but not yet visible to its peers — the symptom otherwise is `MOVED` redirect storms when clients query the new pod and it doesn't yet know its slot ownership.

### preStop — graceful master failover

Set `terminationGracePeriodSeconds: 60` so the preStop hook has time to complete before SIGKILL:

```sh
# /scripts/prestop.sh (essentials)
role=$(valkey-cli info replication | awk -F: '/^role:/ {print $2}' | tr -d '\r')
node_id=$(valkey-cli cluster nodes | awk '/myself/ {print $1}')

if [ "$role" = "master" ]; then
  # Find a slave of mine and trigger TAKEOVER
  slave=$(valkey-cli cluster nodes | awk -v me="$node_id" '$4==me && /slave/ {print $2; exit}' | cut -d@ -f1)
  if [ -n "$slave" ]; then
    valkey-cli -h "${slave%:*}" -p "${slave##*:}" cluster failover takeover
  fi
fi

# Tell every peer to forget me — keeps gossip tables clean
for peer in $(valkey-cli cluster nodes | grep -v myself | awk '{print $2}' | cut -d@ -f1); do
  valkey-cli -h "${peer%:*}" -p "${peer##*:}" cluster forget "$node_id" &
done
wait

valkey-cli shutdown save
```

Without this, master pod restarts cause a 10–15 second write outage per shard while gossip detects the failure and elects a new primary. With it, restarts are sub-second from the client's point of view because failover is initiated *before* the pod stops accepting writes.

## Deployment

The example manifests deploy alongside the replication-mode default in a separate namespace:

```bash
kubectl apply -f data-stacks/valkey-on-eks/examples/cluster-mode/
```

Order of resources matters slightly (the StatefulSet's `volumeClaimTemplates` need the StorageClass to exist; the Secret needs to exist before the StatefulSet pulls the auth):

```bash
# Apply in order — kustomize would handle this automatically
for f in namespace.yaml secret.yaml configmap-config.yaml configmap-scripts.yaml \
         serviceaccount.yaml service-headless.yaml service-client.yaml pdb.yaml \
         networkpolicy.yaml statefulset.yaml; do
  kubectl apply -f data-stacks/valkey-on-eks/examples/cluster-mode/$f
done
```

Watch the bootstrap:

```bash
kubectl -n valkey-cluster get pods -w
# valkey-cluster-0   0/1   ContainerCreating
# valkey-cluster-0   1/1   Running          (bootstrap script kicks off)
# valkey-cluster-1   0/1   ContainerCreating  (OrderedReady — pod 1 starts after pod 0 is Ready)
# ...
# valkey-cluster-5   1/1   Running

# Watch the bootstrap on pod-0
kubectl -n valkey-cluster logs valkey-cluster-0 -f | grep -E '(cluster|MEET|REPLICATE|create)'
```

Verify cluster health:

```bash
PASS=$(kubectl -n valkey-cluster get secret valkey-cluster-auth -o jsonpath='{.data.default}' | base64 -d)

kubectl -n valkey-cluster exec valkey-cluster-0 -c valkey -- \
  valkey-cli -a "$PASS" --no-auth-warning cluster info
# cluster_state:ok
# cluster_slots_assigned:16384
# cluster_slots_ok:16384
# cluster_known_nodes:6
# cluster_size:3

kubectl -n valkey-cluster exec valkey-cluster-0 -c valkey -- \
  valkey-cli -a "$PASS" --no-auth-warning cluster nodes
# Output: 6 lines, 3 marked `master`, 3 marked `slave`, all `connected`,
# slave→master `<slave-id> <slave-addr>... slave <master-id> 0 ...`
```

## Connecting Clients

Cluster mode requires a **cluster-aware client**. Cluster-aware clients understand `MOVED` and `ASK` redirects, refresh slot maps after topology changes, and route same-slot multi-key operations correctly.

| Library | Cluster-aware client class |
|---|---|
| `redis-py` | `redis.cluster.RedisCluster` |
| `redis-py-cluster` (legacy) | use `redis-py` ≥ 4.1 instead |
| Lettuce (Java) | `RedisClusterClient` |
| Jedis | `JedisCluster` |
| ioredis | `Redis.Cluster` |
| `go-redis` | `redis.NewClusterClient` |
| valkey-glide | native cluster mode support |

Connect via the **headless Service**:

```python
from redis.cluster import RedisCluster, ClusterNode

nodes = [ClusterNode(f"valkey-cluster-{i}.valkey-cluster-headless.valkey-cluster.svc.cluster.local", 6379)
         for i in range(6)]
client = RedisCluster(startup_nodes=nodes, password=os.environ["VALKEY_PASSWORD"], decode_responses=True)
client.set("user:42:profile", "carol@example.com")
client.get("user:42:profile")    # cluster client follows MOVED redirect to the right shard
```

The cluster client calls `CLUSTER SLOTS` (or `CLUSTER SHARDS` on Valkey 7.2+) once at startup to learn the slot→primary map, then routes every command directly to the owning primary. Writes go to primaries; reads go to primaries by default — clients that want to load-balance reads across replicas issue `READONLY` after the connection is established.

## Best Practices

### Persistence (required for cluster mode)

Always enable AOF + RDB:

```ini
appendonly yes
appendfsync everysec
save 900 1
save 300 10
save 60 10000
```

Without persistence, a pod restart restores an empty dataset. The replica resyncs via PSYNC from the primary — fine in steady state, but during a controlled rolling restart of the entire cluster (e.g., AMI bump), the first pod back up must have its data on disk or the cluster permanently loses that shard's keyspace.

### AZ spread (the strict version)

Use `whenUnsatisfiable: DoNotSchedule` to make the spread mandatory. With 6 pods and 3 AZs, two pods land per AZ — pair them so a primary and its replica are never in the same AZ:

```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app.kubernetes.io/name: valkey-cluster
```

Cluster bootstrap (`valkey-cli --cluster create --cluster-replicas 1`) does not natively respect AZ topology when assigning replicas — it picks the next pod in the list. To enforce primary→replica AZ separation, run the bootstrap with an **explicit node list** that interleaves AZs:

```bash
# Get pod-to-AZ map
kubectl -n valkey-cluster get pods -o json | jq -r '
  .items[] |
  "\(.metadata.name) \(.spec.nodeName)"' | \
while read pod node; do
  az=$(kubectl get node "$node" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}')
  echo "$pod $az"
done

# Manually create the cluster with primaries 0/1/2 in distinct AZs
# and replicas 3/4/5 mapped to primaries in different AZs:
valkey-cli --cluster create \
  valkey-cluster-0.valkey-cluster-headless...:6379 \
  valkey-cluster-1.valkey-cluster-headless...:6379 \
  valkey-cluster-2.valkey-cluster-headless...:6379 \
  valkey-cluster-3.valkey-cluster-headless...:6379 \
  valkey-cluster-4.valkey-cluster-headless...:6379 \
  valkey-cluster-5.valkey-cluster-headless...:6379 \
  --cluster-replicas 1
# valkey-cli pairs replicas to primaries in declaration order; verify with CLUSTER NODES
# and use CLUSTER REPLICATE to fix any same-AZ pairs.
```

After the cluster is formed, a verification script:

```bash
PASS=$(kubectl -n valkey-cluster get secret valkey-cluster-auth -o jsonpath='{.data.default}' | base64 -d)
kubectl -n valkey-cluster exec valkey-cluster-0 -c valkey -- \
  valkey-cli -a "$PASS" --no-auth-warning cluster nodes | \
  awk '/master/ {m[$1]=$2} /slave/ {pairs[$1]=$4 " " $2} END {
    for (s in pairs) {
      split(pairs[s], a, " ");
      m_id = a[1]; s_addr = a[2];
      printf "slave %s replicates master %s\n", s_addr, m[m_id]
    }
  }'
```

Cross-reference with the pod-to-AZ map; any same-AZ pair needs a manual `CLUSTER REPLICATE` to migrate.

### Network policy

Cluster mode requires unrestricted east-west traffic between Valkey pods on **both** `:6379` and `:16379`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: valkey-cluster
  namespace: valkey-cluster
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: valkey-cluster
  policyTypes: ["Ingress", "Egress"]
  ingress:
    # Allow other Valkey pods in the same namespace
    - from:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: valkey-cluster
      ports:
        - { protocol: TCP, port: 6379 }
        - { protocol: TCP, port: 16379 }
    # Allow application namespaces (replace with your actual app namespace)
    - from:
        - namespaceSelector:
            matchLabels:
              role: app
      ports:
        - { protocol: TCP, port: 6379 }
    # Allow Prometheus
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: monitoring
      ports:
        - { protocol: TCP, port: 9121 }
  egress:
    # Allow cluster bus + replication to peers
    - to:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: valkey-cluster
      ports:
        - { protocol: TCP, port: 6379 }
        - { protocol: TCP, port: 16379 }
    # DNS
    - to:
        - namespaceSelector: {}
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - { protocol: UDP, port: 53 }
```

### PodDisruptionBudget

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: valkey-cluster
  namespace: valkey-cluster
spec:
  maxUnavailable: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: valkey-cluster
```

`maxUnavailable: 1` is the right call: cluster mode tolerates **one primary down** because failover requires a majority of the remaining 2 primaries to agree (2/3 = quorum). Setting `maxUnavailable: 2` could remove 2 primaries simultaneously and stall failover.

For deeper safety during voluntary disruptions (drains, node replacements), pair the PDB with `pod-deletion-cost` annotations to bias eviction toward replicas first:

```yaml
annotations:
  controller.kubernetes.io/pod-deletion-cost: "-100"   # set on replicas; primaries get +100
```

### Sizing

| Workload | Pod size (memory request = limit) | Node instance | Total cluster memory (3 primaries) |
|---|---|---|---|
| Dev / staging | 4 GiB | `r7g.large` (16 GiB) | 12 GiB primary capacity |
| Small prod | 12 GiB | `r7g.large` (16 GiB) | 36 GiB |
| Medium prod | 24 GiB | `r7g.xlarge` (32 GiB) | 72 GiB |
| Large prod | 48 GiB | `r7g.2xlarge` (64 GiB) | 144 GiB |
| Very large | 96 GiB | `r7g.4xlarge` (128 GiB) | 288 GiB |

Always set `requests.memory == limits.memory`. Set `maxmemory` in `valkey.conf` to ~80% of `requests.memory`. The remainder is fork-time CoW headroom for `BGSAVE`. Set `maxmemory-policy noeviction` so the cluster prefers write rejection over eviction (eviction in cluster mode complicates slot ownership).

## Operational Runbooks

### Scale out (add a shard)

Cluster mode scales by adding shards (a primary + its replica), not by adding pods to existing shards.

```bash
# 1. Bump replicas in the StatefulSet
kubectl -n valkey-cluster scale statefulset valkey-cluster --replicas=8

# 2. Wait for the new pods to be Running and Ready
kubectl -n valkey-cluster rollout status statefulset/valkey-cluster

# 3. Have the new primary join the cluster (init script does this automatically,
#    but for an explicit shard add, use --cluster add-node)
PASS=$(kubectl -n valkey-cluster get secret valkey-cluster-auth -o jsonpath='{.data.default}' | base64 -d)

# Add new primary (pod 6)
kubectl -n valkey-cluster exec valkey-cluster-0 -c valkey -- \
  valkey-cli -a "$PASS" --no-auth-warning --cluster add-node \
    valkey-cluster-6.valkey-cluster-headless.valkey-cluster.svc.cluster.local:6379 \
    valkey-cluster-0.valkey-cluster-headless.valkey-cluster.svc.cluster.local:6379

# Reshard hash slots — move 4096 slots from existing primaries to the new one
kubectl -n valkey-cluster exec valkey-cluster-0 -c valkey -- \
  valkey-cli -a "$PASS" --no-auth-warning --cluster reshard \
    valkey-cluster-0.valkey-cluster-headless.valkey-cluster.svc.cluster.local:6379 \
    --cluster-from all --cluster-to <new-primary-node-id> \
    --cluster-slots 4096 --cluster-yes

# Add the new replica (pod 7) and assign it to the new primary
kubectl -n valkey-cluster exec valkey-cluster-0 -c valkey -- \
  valkey-cli -a "$PASS" --no-auth-warning --cluster add-node \
    valkey-cluster-7.valkey-cluster-headless.valkey-cluster.svc.cluster.local:6379 \
    valkey-cluster-0.valkey-cluster-headless.valkey-cluster.svc.cluster.local:6379 \
    --cluster-slave --cluster-master-id <new-primary-node-id>
```

Plan for **15–30 minutes of rebalancing per 10 GiB of data**. Resharding is online — clients see brief `MOVED` redirects but no errors.

### Recover from quorum loss

If 2+ primaries fail simultaneously (e.g., 2 AZs go down), the surviving primary cannot fail over its slot range — it has no quorum. The cluster reports `cluster_state:fail` and rejects writes.

Recovery:

```bash
# 1. Restore the failed pods (Karpenter brings new nodes; pods rejoin via init script)
kubectl -n valkey-cluster get pods   # wait for all 6 pods to be Running

# 2. If pods rejoin but the cluster stays in fail state, force a slot takeover
#    on each surviving primary:
PASS=$(kubectl -n valkey-cluster get secret valkey-cluster-auth -o jsonpath='{.data.default}' | base64 -d)
for pod in valkey-cluster-0 valkey-cluster-1 valkey-cluster-2; do
  kubectl -n valkey-cluster exec "$pod" -c valkey -- \
    valkey-cli -a "$PASS" --no-auth-warning cluster reset hard 2>/dev/null || true
done
# Then re-bootstrap from the freshest primary's nodes.conf (in PVC):
# Restore the cluster.conf from PVC backup, restart all pods.
```

If `nodes.conf` on disk is corrupted across multiple PVCs, the only path is **restore from RDB backup**: `kubectl exec` into each surviving pod, copy `/data/dump.rdb` and `/data/appendonly.aof.*` out via S3, then redeploy a fresh cluster and restore via the [EC2 → EKS migration runbook](./ec2-migration.md) per shard.

### Forced primary failover (planned)

To rotate the primary role onto a specific replica (e.g., for a planned upgrade of the current primary's underlying node):

```bash
# Find the replica ordinal that should become primary (e.g., valkey-cluster-3 replicates valkey-cluster-0)
PASS=$(kubectl -n valkey-cluster get secret valkey-cluster-auth -o jsonpath='{.data.default}' | base64 -d)

# On the replica, issue the failover (FORCE makes it skip the consensus wait — use sparingly)
kubectl -n valkey-cluster exec valkey-cluster-3 -c valkey -- \
  valkey-cli -a "$PASS" --no-auth-warning cluster failover

# Verify role flipped
kubectl -n valkey-cluster exec valkey-cluster-3 -c valkey -- \
  valkey-cli -a "$PASS" --no-auth-warning info replication | grep '^role:'
# role:master
```

## Roll Your Own

The example manifests are intended as a starting point. Customize them by:

1. **Tuning shard count**: change `replicas` in the StatefulSet (must stay even — half are primaries, half are replicas under the default 1:1 layout) and update `REPLICAS` env var on the bootstrap script.
2. **Tuning replicas per primary**: pass `--cluster-replicas N` (instead of `1`) to the bootstrap script, and set `replicas` to `primaries × (1 + N)`.
3. **Tuning persistence**: drop `appendonly yes` if you want RDB-only (faster but coarser durability). Increase the `save` cadence for tighter RPO.
4. **Tuning eviction**: switch `maxmemory-policy` to `allkeys-lru` if you can tolerate eviction (cache-mode), but understand that eviction reshuffles slot ownership semantics and complicates client behavior.
5. **TLS**: set `tls-port 6379` and `port 0` in `valkey.conf`, mount cert/key/CA from a secret, update the readiness/preStop scripts to use `--tls --cert ... --key ... --cacert ...`. Lettuce / `redis-py` ≥ 4.1 / Jedis 4+ support cluster TLS natively.

## Migration: Replication → Cluster

Already running this stack's replication mode and want to migrate to cluster mode without downtime?

1. Deploy the cluster-mode manifests in a separate namespace (`valkey-cluster`) so both releases run in parallel.
2. Use `valkey-cli --cluster import` from a temporary client pod to copy keys from the replication primary into the cluster:
   ```bash
   kubectl run valkey-cli --rm -it --image=docker.io/valkey/valkey:9.0.2 --restart=Never -- /bin/sh
   valkey-cli --cluster import \
     valkey-cluster-0.valkey-cluster-headless.valkey-cluster.svc.cluster.local:6379 \
     --cluster-from valkey.valkey.svc.cluster.local:6379 \
     --cluster-from-pass "$REPLICATION_PASS" \
     --cluster-from-user default \
     --cluster-to valkey-cluster-0.valkey-cluster-headless.valkey-cluster.svc.cluster.local:6379 \
     --cluster-replace
   ```
3. Cut application traffic over to the cluster mode endpoints (a cluster-aware client library is required — see the client compatibility table earlier).
4. Once stable, decommission the replication-mode release.

`--cluster import` does live key migration with `DUMP` / `RESTORE`. Expect throughput around 5–20 MB/s per source connection; for very large datasets, parallelize by hash-slot range.

## References

- [valkey-helm PR #51](https://github.com/valkey-io/valkey-helm/pull/51) — the upstream PR this design is based on.
- [valkey-helm issue #18](https://github.com/valkey-io/valkey-helm/issues/18) — tracking native cluster support in the official chart.
- [Valkey Cluster Specification](https://valkey.io/topics/cluster-spec/) — protocol-level reference for slot assignment, gossip, failover.
- [Valkey Cluster Tutorial](https://valkey.io/topics/cluster-tutorial/) — the hands-on companion to the spec.
