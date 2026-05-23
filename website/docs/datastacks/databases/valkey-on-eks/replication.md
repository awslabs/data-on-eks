---
title: Replication Cluster
sidebar_position: 2
---

# Replication Cluster — Verification and Testing

The default deployment is a Valkey replication topology: one **primary** that accepts writes, and N **replicas** that asynchronously replicate the primary's keyspace and serve reads. The chart ships three Services for client traffic — pick the right one for read versus write paths.

## Endpoints

| Service | Type | Selector | Use for |
|---|---|---|---|
| `valkey` | ClusterIP | primary only | Writes |
| `valkey-read` | ClusterIP | all 4 pods (primary + 3 replicas) | Reads (load-balanced) |
| `valkey-headless` | ClusterIP `None` | all pods, per-pod DNS | Cluster-internal replication, application clients that need stable per-pod addressing |
| `valkey-metrics` | ClusterIP | all pods | Prometheus scrape on `:9121` |

The chart wires the Service-to-pod selector via the `app.kubernetes.io/component=master|replica` label, so the `valkey` Service follows the primary even after a manual failover (`REPLICAOF NO ONE` flips the label).

## Verification

### 1. Pods are 2/2 Running

```bash
kubectl -n valkey get pods -o wide
```

Each pod should report `2/2 Running`. The two containers are `valkey` (the data plane) and `metrics` (the `oliver006/redis_exporter` sidecar).

### 2. Replication health from the primary

```bash
PASS=$(kubectl -n valkey get secret valkey-auth -o jsonpath='{.data.default}' | base64 -d)

kubectl -n valkey exec valkey-0 -c valkey -- \
  valkey-cli -a "$PASS" --no-auth-warning INFO replication
```

Expected output:

```
# Replication
role:master
connected_slaves:3
min_slaves_good_slaves:3
slave0:ip=valkey-1.valkey-headless.valkey.svc.cluster.local,port=6379,state=online,offset=...,lag=0,type=replica
slave1:ip=valkey-2.valkey-headless.valkey.svc.cluster.local,port=6379,state=online,offset=...,lag=0,type=replica
slave2:ip=valkey-3.valkey-headless.valkey.svc.cluster.local,port=6379,state=online,offset=...,lag=0,type=replica
master_failover_state:no-failover
master_replid:<40-char hex>
```

Three properties to assert:

- `role:master` on `valkey-0`.
- `connected_slaves` matches `replica.replicas` from `helm-values/valkey.yaml`.
- Every slave reports `state=online` with `lag` ≤ `replica.minReplicasMaxLag` (default 10s).

### 3. AZ spread

```bash
kubectl -n valkey get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.nodeName}{"\n"}{end}' | \
  while read p n; do
    az=$(kubectl get node "$n" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}')
    echo "$p  $az"
  done
```

With `replica.replicas=3` (4 pods total) on a 3-AZ cluster, expect three pods across distinct AZs and the fourth in the AZ with the most spare capacity. The chart's `topologySpreadConstraints` use `whenUnsatisfiable: DoNotSchedule`, so any pod failing to find an AZ stays `Pending` rather than colocating.

### 4. ServiceMonitor is registered

```bash
kubectl -n monitoring get servicemonitor valkey -o yaml | head -30
```

`kube-prometheus-stack` discovers any `ServiceMonitor` whose namespaceSelector matches its release namespace. Confirm Prometheus is scraping `:9121`:

```bash
kubectl -n monitoring port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 &
curl -s 'http://localhost:9090/api/v1/targets?state=active' | \
  jq '.data.activeTargets[] | select(.labels.job=="valkey") | .health'
# "up" (× number of pods)
```

## Smoke Test

Apply the bundled smoke-test Job, which writes against the primary service and reads back from the load-balanced read service:

```bash
kubectl apply -f data-stacks/valkey-on-eks/examples/valkey-replication-smoke.yaml
kubectl -n valkey logs -f job/valkey-smoke
```

Expected log output:

```
=== Valkey replication smoke test ===
Write target: valkey.valkey.svc.cluster.local:6379
Read  target: valkey-read.valkey.svc.cluster.local:6379

--- PING primary and read service ---
primary: PONG
read   : PONG

--- WRITE three keys to the primary ---
  SET user:1:profile -> OK
  SET user:42:profile -> OK
  SET user:9999:profile -> OK

--- READ keys back from valkey-read (with brief retry for lag) ---
  GET user:1:profile -> value-for-user:1:profile
  GET user:42:profile -> value-for-user:42:profile
  GET user:9999:profile -> value-for-user:9999:profile

--- Replication health (from primary) ---
role:master
connected_slaves:3
min_slaves_good_slaves:3
slave0:ip=...,state=online,...
slave1:ip=...,state=online,...
slave2:ip=...,state=online,...

smoke test PASSED
```

The Job retries each read up to five times (1-second backoff) to absorb transient replication lag. If a single GET miss occurs after retries, the Job exits non-zero — that signals a real replication problem worth investigating.

The Job is idempotent; the keys are overwritten on each run. It auto-cleans 1 hour after completion (`ttlSecondsAfterFinished: 3600`).

### Smoke test from your application's namespace

The bundled Job runs in the `valkey` namespace. To test from your application's namespace, copy the manifest and change `metadata.namespace` plus the AUTH `secretKeyRef` to point at a same-namespace copy of the secret. The DNS names (`valkey.valkey.svc.cluster.local`, `valkey-read.valkey.svc.cluster.local`) are valid from any namespace as long as your NetworkPolicy allows egress on TCP 6379 to the `valkey` namespace.

## Read/Write Split for Application Clients

The two-Service pattern is intentional. Configure your client library:

| Client library | Configuration |
|---|---|
| **redis-py / redis-py-cluster** | `Redis(host="valkey.valkey.svc.cluster.local", ...)` for writes; second `Redis(host="valkey-read...", ...)` for reads. |
| **ioredis** | Use `Redis` (single endpoint); set `enableReadyCheck: false` and route reads through a separate connection pool to `valkey-read`. |
| **Lettuce (Java)** | `RedisStaticMasterReplicaClient`-style connections; primary URI to `valkey`, replica URIs to `valkey-read`, set `ReadFrom.REPLICA_PREFERRED`. |
| **Jedis** | `JedisPooled` for primary; `JedisPooled` for replicas via `valkey-read`. Multi-pool routing is application-side. |
| **go-redis (v9+)** | `redis.NewFailoverClient` with explicit master/replica URIs. |
| **valkey-glide** | Native primary/replica routing — point at `valkey-headless` and let the client handle role discovery via `REPLICAOF` introspection. |

The `valkey-read` Service is a kube-proxy round-robin across all four pods (including the primary, since the primary serves reads consistently with replicas). To exclude the primary from reads, switch your client to `valkey-headless` and filter by the `role` field of `INFO replication` — most cluster-aware libraries do this automatically.

## Manual Primary Failover

To promote a replica to primary (e.g., before restarting `valkey-0` for an upgrade):

```bash
PASS=$(kubectl -n valkey get secret valkey-auth -o jsonpath='{.data.default}' | base64 -d)

# Promote valkey-1 to primary
kubectl -n valkey exec valkey-1 -c valkey -- \
  valkey-cli -a "$PASS" --no-auth-warning REPLICAOF NO ONE

# Re-point remaining replicas at the new primary
for ord in 2 3; do
  kubectl -n valkey exec valkey-${ord} -c valkey -- \
    valkey-cli -a "$PASS" --no-auth-warning REPLICAOF \
      valkey-1.valkey-headless.valkey.svc.cluster.local 6379
done

# Verify
kubectl -n valkey exec valkey-1 -c valkey -- \
  valkey-cli -a "$PASS" --no-auth-warning INFO replication | grep -E '^(role|connected_slaves):'
# role:master
# connected_slaves:2  (will become 3 once valkey-0 catches up)
```

The `valkey` Service follows the primary via the chart's component-label selector, so client traffic re-routes automatically once the replica's `app.kubernetes.io/component` label flips to `master`. The chart writes a 0-second TTL `valkey.conf` reload on `REPLICAOF NO ONE` — no pod restart required.

To restore the original layout (`valkey-0` as primary), run the same `REPLICAOF` sequence in reverse.

:::warning
Async replication means writes accepted by the old primary in the seconds before the failover may not have reached the new primary. For a planned failover, pause writes for ~5 seconds (`min_slaves_good_slaves` provides a partial guard) before issuing `REPLICAOF NO ONE`. For an unplanned failover (primary pod crash), the data loss window is bounded by `replica.minReplicasMaxLag`.
:::

## Resilience Behavior

| Failure | Behavior | Recovery |
|---|---|---|
| Replica pod crash | StatefulSet recreates the pod; replica re-syncs (full or partial PSYNC depending on backlog) | Automatic |
| Primary pod crash | No automatic failover (this is replication mode, not Sentinel/cluster). Writes are rejected (`min_slaves_good_slaves` stops gating; clients see `LOADING` or connection refused). | Manual `REPLICAOF NO ONE` on a replica |
| Node failure (Karpenter-provisioned) | Karpenter provisions a replacement node in the same AZ when possible; pod is rescheduled with the same PVC | Automatic, ~2–5 min |
| AZ failure | Pods in the failed AZ stay `Pending`. The two healthy AZs continue to serve reads from in-sync replicas. Writes via the primary continue if the primary is in a healthy AZ. | Manual failover if the primary was in the failed AZ |
| Cross-AZ replication lag spike | `min_slaves_good_slaves` drops; primary may reject writes if `minReplicasToWrite` is set | Wait for replicas to catch up; investigate network |

For automatic primary failover, the Valkey project's options are Sentinel (not yet in the official chart) or cluster mode (tracked at [valkey-helm #18](https://github.com/valkey-io/valkey-helm/issues/18)). Until either ships, the recommended pattern is to monitor `valkey_master_link_up` per replica and trigger `REPLICAOF NO ONE` from your alerting pipeline.

## Observability

The data stack ships [`kube-prometheus-stack`](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) in the `monitoring` namespace. Both Valkey clusters (replication and cluster mode) are scraped automatically via their `ServiceMonitor`s — no extra wiring needed. The exporter is `oliver006/redis_exporter` (sidecar in each pod), so metrics use the `redis_*` prefix even though the server is Valkey.

### Key metrics and alerts

| Metric | Meaning | Suggested alert |
|---|---|---|
| `redis_up` | Exporter could scrape the pod | `for 2m`, severity critical |
| `redis_master_link_up` | Replica's link to primary is healthy | `== 0 for 2m`, severity critical |
| `redis_master_last_io_seconds_ago` | Seconds since the replica last received from the primary | `> 30 for 5m`, severity warning |
| `redis_connected_slaves` | Replicas the primary sees as connected | `< replica.replicas for 5m`, severity warning |
| `redis_memory_used_bytes / redis_memory_max_bytes` | Memory pressure | `> 0.9 for 10m`, severity warning |
| `redis_evicted_keys_total` | Keys evicted under memory pressure | `increase > 0 for 5m`, severity warning |

### Verify the scrape is healthy

```bash
# Both Valkey clusters should return redis_up=1.
kubectl -n monitoring exec prometheus-prometheus-0 -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/query?query=redis_up' | jq '.data.result[].metric | {pod, namespace}'
```

Expect one entry per Valkey pod, e.g. `{pod: valkey-0, namespace: valkey}` and (if cluster mode is also installed) `{pod: valkey-cluster-0, namespace: valkey-cluster}`.

### Access Grafana

Grafana is deployed as `monitoring/monitoring-grafana` (ClusterIP). The data stack creates an admin secret with a randomly generated password.

```bash
# 1. Pull the admin password from the cluster.
kubectl -n monitoring get secret grafana-admin-secret \
  -o jsonpath='{.data.admin-password}' | base64 -d; echo

# 2. Port-forward Grafana to localhost.
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80
```

Open [http://localhost:3000](http://localhost:3000) and log in:

- **User:** `admin`
- **Password:** the value printed by step 1

The Prometheus data source is already wired. Open **Explore** (compass icon) and run `redis_up` to confirm metrics are flowing. Useful starting queries:

```promql
# Active connections per pod
redis_connected_clients{namespace="valkey"}

# Throughput in ops/sec
sum by (pod) (rate(redis_commands_processed_total{namespace="valkey"}[1m]))

# Cache hit rate
sum(rate(redis_keyspace_hits_total{namespace="valkey"}[5m]))
  / sum(rate(redis_keyspace_hits_total{namespace="valkey"}[5m]) + rate(redis_keyspace_misses_total{namespace="valkey"}[5m]))

# Replication lag in seconds (per replica)
redis_master_last_io_seconds_ago{namespace="valkey"}

# Memory headroom
redis_memory_used_bytes{namespace="valkey"} / redis_memory_max_bytes{namespace="valkey"}
```

### Import the bundled dashboard

A starter dashboard ships at [`data-stacks/valkey-on-eks/examples/grafana-valkey-dashboard.json`](https://github.com/awslabs/data-on-eks/blob/main/data-stacks/valkey-on-eks/examples/grafana-valkey-dashboard.json). Two ways to load it.

**Option 1 — auto-import via ConfigMap (recommended for repeatable installs).**

The Grafana sidecar (`grafana-sc-dashboard`, label selector `grafana_dashboard=1`) watches every namespace and auto-imports any matching ConfigMap.

```bash
kubectl create configmap valkey-grafana-dashboard \
  --namespace monitoring \
  --from-file=valkey.json=data-stacks/valkey-on-eks/examples/grafana-valkey-dashboard.json
kubectl label configmap valkey-grafana-dashboard \
  --namespace monitoring \
  grafana_dashboard=1
```

The dashboard appears under **Dashboards → Browse** within ~30 seconds. Use the `namespace` template variable at the top to switch between `valkey` (replication) and `valkey-cluster` (cluster mode).

**Option 2 — manual import via the UI.**

Grafana → **Dashboards → New → Import** → paste the JSON file's contents → pick the **Prometheus** data source → **Import**. Faster for ad-hoc inspection, doesn't survive a Grafana restart.

**Option 3 — community dashboard.** If the bundled dashboard panels show "No data" because of a metric-prefix mismatch on older exporter versions, [dashboard 11835](https://grafana.com/grafana/dashboards/11835-redis-dashboard-for-prometheus-redis-exporter-1-x/) ("Redis Dashboard for Prometheus Redis Exporter 1.x") is a known-good fallback for the same exporter family.

### Direct Prometheus access

For PromQL queries against raw metrics or to inspect target health:

```bash
kubectl -n monitoring port-forward svc/prometheus-prometheus 9090:9090
# http://localhost:9090
```

Check **Status → Targets** and filter on `valkey` — both `valkey/valkey/0` (replication) and `valkey-cluster/valkey-cluster/0` (cluster mode, if installed) should show `UP`.
