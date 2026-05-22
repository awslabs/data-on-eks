---
title: Sample Workload — Hits Dataset
sidebar_label: Sample Workload
sidebar_position: 2
---

import '@site/src/css/clickhouse-architecture.css';

This walkthrough deploys a sharded, replicated `ClickHouseCluster` (managed
by the operator that `deploy.sh` already installed), builds a distributed
table on top of it, loads the public `hits` dataset, runs analytical queries
with `EXPLAIN` to inspect index usage, and demonstrates replica failover by
deleting a pod.

## Prerequisites

- **ClickHouse on EKS infrastructure deployed**: You must have completed the
  [Infrastructure Setup Guide](./infra.md). That sets up the EKS cluster,
  Karpenter, ArgoCD, and the ClickHouse Kubernetes operator — but **no
  `ClickHouseCluster` yet**. This guide deploys one.
- **Local tools**:
  - `kubectl` configured against the EKS cluster (the deploy script writes
    `kubeconfig.yaml` into the stack directory —
    `export KUBECONFIG=$(pwd)/kubeconfig.yaml`).
  - `aws-cli` with credentials configured.

## Architecture

The example manifest at
`data-stacks/clickhouse-on-eks/examples/clickhouse-cluster.yaml` defines two
custom resources that the operator reconciles into running pods: a
`ClickHouseCluster` (3 shards × 3 replicas) and a `KeeperCluster` (3-node
Raft ensemble). Together they form the data plane this walkthrough exercises.

<div className="ch-arch-diagram">
  <div className="ch-arch-operator-wrapper">
    <div className="ch-arch-operator-label">ClickHouse Operator</div>

    {/* ClickHouse Nodes Layer */}
    <div className="ch-arch-layer">
      <div className="ch-arch-layer-label">
        <b>ClickHouseCluster</b> — 3 shards × 3 replicas — m6g.8xlarge · 30 CPU · 110Gi RAM · 500Gi storage
      </div>
      <div className="ch-arch-nodes">
        {[1, 2, 3].map((shard) => (
          <div className="ch-arch-shard" key={shard}>
            <div className="ch-arch-shard-label">Shard {shard}</div>
            {[1, 2, 3].map((replica) => (
              <div className="ch-arch-node" key={replica}>
                <svg className="ch-arch-node-icon" viewBox="0 0 14 14" fill="none" stroke="var(--ch-amber)" strokeWidth="1">
                  <rect x="1" y="3" width="12" height="9" rx="1.5" />
                  <line x1="1" y1="6" x2="13" y2="6" />
                  <circle cx="3.5" cy="8.5" r="0.8" fill="var(--ch-amber)" />
                </svg>
                Replica {replica}
              </div>
            ))}
          </div>
        ))}
      </div>
    </div>

    {/* Coordination lines */}
    <div className="ch-arch-coordination">
      <svg viewBox="0 0 600 40" preserveAspectRatio="none">
        <path className="ch-arch-coordination-line" d="M100,0 L100,40" />
        <path className="ch-arch-coordination-line" d="M300,0 L300,40" style={{ animationDelay: '-0.5s' }} />
        <path className="ch-arch-coordination-line" d="M500,0 L500,40" style={{ animationDelay: '-1s' }} />
      </svg>
      <div className="ch-arch-coordination-labels">
        <span>replication</span>
        <span>distributed DDL</span>
        <span>leader election</span>
      </div>
    </div>

    {/* Keeper Layer */}
    <div className="ch-arch-layer">
      <div className="ch-arch-layer-label">
        <b>KeeperCluster</b> — 3 nodes, Raft consensus
      </div>
      <div className="ch-arch-keeper-nodes">
        {[1, 2, 3].map((id) => (
          <div className="ch-arch-keeper-node" key={id}>
            <svg className="ch-arch-node-icon" viewBox="0 0 14 14" fill="none" stroke="var(--ch-blue)" strokeWidth="1">
              <circle cx="7" cy="7" r="5.5" />
              <path d="M7 4v3l2 2" />
            </svg>
            Keeper {id}
          </div>
        ))}
      </div>
    </div>

  </div>
</div>

- **ClickHouse Operator:** Already installed by `deploy.sh`. Watches `ClickHouseCluster` and `KeeperCluster` custom resources and reconciles them into pods, services, and PersistentVolumeClaims.
- **ClickHouseCluster:** A sharded and replicated deployment (3 shards × 3 replicas) running on Graviton `m6g.8xlarge` nodes with 500Gi EBS volumes per replica. Karpenter provisions the underlying EC2 instances on demand.
- **KeeperCluster:** A 3-node ClickHouse Keeper ensemble providing Raft-based coordination for replication, distributed DDL, and leader election.


## Deploy the ClickHouse cluster

These steps apply the example manifest and bring up the data plane shown
above. They produce 3 Keeper pods plus 9 ClickHouse pods named
`tests-clickhouse-<shard>-<replica>-0`.


### 1. Create the namespace

The example manifest places everything in the `clickhouse-tests` namespace.
Create it first:

```bash
kubectl create namespace clickhouse-tests
```


### 2. Create the password secret

The `ClickHouseCluster` resource references a Kubernetes secret for the
`default` user's password (see `defaultUserPassword.secret` in the cluster
manifest). Create it **before** applying the cluster manifest so the operator
can bootstrap the user when the pods come up.

```bash
kubectl create secret generic clickhouse-password \
  --namespace clickhouse-tests \
  --from-literal=password="$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32)"
```

The `tr`/`/dev/urandom` pipeline generates a 32-character alphanumeric
password — `LC_ALL=C` keeps `tr` from choking on multi-byte locales.


### 3. Apply the cluster manifest

```bash
export CLICKHOUSE_DIR=$(git rev-parse --show-toplevel)/data-stacks/clickhouse-on-eks
kubectl apply -f $CLICKHOUSE_DIR/examples/clickhouse-cluster.yaml
```

The operator reads the new `KeeperCluster` and `ClickHouseCluster` resources
and starts reconciling them. Because the `ClickHouseCluster` `podTemplate`
sets a `nodeSelector` for `m6g.8xlarge` on-demand instances, Karpenter
provisions matching EC2 nodes from scratch the first time you apply this.


### 4. Wait for the pods to be Ready

```bash
kubectl get pods -n clickhouse-tests -w
```

Expected steady state — 3 Keeper pods and 9 ClickHouse pods, all `Running` /
`Ready`:

```text
NAME                       READY   STATUS    RESTARTS   AGE
test-keeper-0              1/1     Running   0          5m
test-keeper-1              1/1     Running   0          5m
test-keeper-2              1/1     Running   0          5m
tests-clickhouse-0-0-0     1/1     Running   0          4m
tests-clickhouse-0-1-0     1/1     Running   0          4m
tests-clickhouse-0-2-0     1/1     Running   0          4m
tests-clickhouse-1-0-0     1/1     Running   0          4m
tests-clickhouse-1-1-0     1/1     Running   0          4m
tests-clickhouse-1-2-0     1/1     Running   0          4m
tests-clickhouse-2-0-0     1/1     Running   0          4m
tests-clickhouse-2-1-0     1/1     Running   0          4m
tests-clickhouse-2-2-0     1/1     Running   0          4m
```

:::info
First-time pod scheduling can take ~5–10 minutes while Karpenter provisions
fresh `m6g.8xlarge` nodes and EBS volumes. Subsequent restarts are much
faster.
:::


## Tutorial: Build a sharded, replicated table

This section creates a database, a replicated local table, and a distributed
"router" table on top of the 3 × 3 ClickHouse cluster, then verifies the layout
end-to-end. It uses the public `hits.parquet` dataset from
[clickhouse.com/datasets](https://datasets.clickhouse.com/) for the schema.


### 1. Open a SQL session

Pull the password back out of the secret and exec into any ClickHouse pod to
get an interactive `clickhouse-client` session. Every pod in the cluster sees
the same logical database, so shard/replica `0-0-0` is fine.

```bash
CH_PW=$(kubectl get secret -n clickhouse-tests clickhouse-password \
  -o jsonpath='{.data.password}' | base64 -d)

kubectl exec -it -n clickhouse-tests tests-clickhouse-0-0-0 -- \
  clickhouse-client --password "$CH_PW"
```

Run the SQL in the following steps from this session.


### 2. Create the database on every node

```sql
CREATE DATABASE IF NOT EXISTS demo ON CLUSTER 'default';
```

`ON CLUSTER 'default'` turns this into a **distributed DDL**: the coordinator
writes the statement to ClickHouse Keeper, and every node in the `default`
cluster picks it up and executes it locally. That's why one `CREATE DATABASE`
materializes the database on all nine pods.


### 3. Create the replicated local table

```sql
CREATE TABLE demo.hits_local ON CLUSTER 'default'
  ENGINE = ReplicatedMergeTree
  ORDER BY (CounterID, EventDate, UserID, EventTime, WatchID)
  EMPTY AS SELECT * FROM s3(
      'https://datasets.clickhouse.com/hits_compatible/hits.parquet',
      'Parquet'
  );
```

A few things are happening here:

- **`ReplicatedMergeTree`** is the actual storage engine. Every replica inside
  a shard keeps an identical copy of the data, with replication coordinated
  through Keeper.
- **`ORDER BY (...)`** is both the sort key and the primary key — it defines
  the on-disk layout and the sparse index ClickHouse uses to skip reading
  irrelevant granules.
- **`EMPTY AS SELECT * FROM s3(...)`** is a schema-cloning trick. The `s3()`
  table function reads only the Parquet metadata to infer column names and
  types, and `EMPTY AS` builds a table with that schema while loading **zero
  rows**. It's a fast way to copy a schema without the data.

Because of `ON CLUSTER`, the table is created on all 9 replicas (3 shards × 3
replicas).


### 4. Create the distributed router table

```sql
CREATE TABLE demo.hits ON CLUSTER 'default' AS demo.hits_local
  ENGINE = Distributed('default', demo, hits_local, cityHash64(UserID));
```

`demo.hits` is a **virtual table that stores no data of its own**. It's a
proxy/router whose `Distributed` engine knows:

- which cluster to talk to (`'default'`),
- which database and underlying table on each shard (`demo.hits_local`),
- and how to shard on writes (`cityHash64(UserID)`).

Reads against `demo.hits` fan out to every shard, execute against the local
`hits_local` table, and the coordinator merges the per-shard results. Writes
against `demo.hits` are routed to a single shard based on the hash of the
`UserID` — that's how rows get distributed evenly. (Writes against
`demo.hits_local` directly only land on whichever replica's pod you're
connected to.)


### 5. Verify the layout

```sql
SELECT hostName(), name, engine
FROM clusterAllReplicas('default', system.tables)
WHERE database = 'demo'
ORDER BY hostName(), name;
```

```text
    ┌─hostName()─────────────┬─name───────┬─engine──────────────┐
 1. │ tests-clickhouse-0-0-0 │ hits       │ Distributed         │
 2. │ tests-clickhouse-0-0-0 │ hits_local │ ReplicatedMergeTree │
 3. │ tests-clickhouse-0-1-0 │ hits       │ Distributed         │
 4. │ tests-clickhouse-0-1-0 │ hits_local │ ReplicatedMergeTree │
 5. │ tests-clickhouse-0-2-0 │ hits       │ Distributed         │
 6. │ tests-clickhouse-0-2-0 │ hits_local │ ReplicatedMergeTree │
 7. │ tests-clickhouse-1-0-0 │ hits       │ Distributed         │
 8. │ tests-clickhouse-1-0-0 │ hits_local │ ReplicatedMergeTree │
 9. │ tests-clickhouse-1-1-0 │ hits       │ Distributed         │
10. │ tests-clickhouse-1-1-0 │ hits_local │ ReplicatedMergeTree │
11. │ tests-clickhouse-1-2-0 │ hits       │ Distributed         │
12. │ tests-clickhouse-1-2-0 │ hits_local │ ReplicatedMergeTree │
13. │ tests-clickhouse-2-0-0 │ hits       │ Distributed         │
14. │ tests-clickhouse-2-0-0 │ hits_local │ ReplicatedMergeTree │
15. │ tests-clickhouse-2-1-0 │ hits       │ Distributed         │
16. │ tests-clickhouse-2-1-0 │ hits_local │ ReplicatedMergeTree │
17. │ tests-clickhouse-2-2-0 │ hits       │ Distributed         │
18. │ tests-clickhouse-2-2-0 │ hits_local │ ReplicatedMergeTree │
    └────────────────────────┴────────────┴─────────────────────┘
```

`clusterAllReplicas('default', system.tables)` runs the query on **every
replica** in the cluster (not just one per shard the way `cluster()` would).
Each pod reports back its own copy of `system.tables`, so the result has
3 shards × 3 replicas × 2 tables = **18 rows**. The pod naming
`tests-clickhouse-<shard>-<replica>-0` is set by the operator and matches the
hostnames returned by `hostName()`.

Recap of what each table is for:

- `hits_local` — `ReplicatedMergeTree`, holds the actual rows on each replica.
- `hits` — `Distributed`, the cluster-wide query entry point that fans out to
  the `hits_local` tables.


### 6. Inspect the primary key and sort key

```sql
SELECT
    name,
    primary_key,
    sorting_key
FROM system.tables
WHERE name = 'hits_local' AND database = 'demo';
```

```text
┌─name───────┬─primary_key──────────────────────────────────────┬─sorting_key──────────────────────────────────────┐
│ hits_local │ CounterID, EventDate, UserID, EventTime, WatchID │ CounterID, EventDate, UserID, EventTime, WatchID │
└────────────┴──────────────────────────────────────────────────┴──────────────────────────────────────────────────┘
```

In ClickHouse the **primary key defaults to the sorting key** (the `ORDER BY`),
and they're shown here side by side. Note this is **not a uniqueness
constraint** — it's a sparse index that lets ClickHouse skip whole granules
when a query filters on a prefix of those columns. Choosing the right
`ORDER BY` is the single biggest performance lever in MergeTree.


### 7. View the materialized table definition

```sql
SHOW CREATE TABLE demo.hits_local;
```

```text
┌─statement─────────────────────────────────────────────────────────────────────────────┐
│ CREATE TABLE demo.hits_local                                                          │
│(                                                                                      │
│    `WatchID` Int64,                                                                   │
│    `JavaEnable` Int16,                                                                │
│    `Title` String,                                                                    │
│    `EventTime` Int64,                                                                 │
│    `EventDate` UInt16,                                                                │
│    `ClientIP` Int32,                                                                  │
│    `RegionID` Int32,                                                                  │
│    `UserID` Int64,                                                                    │
│    `CounterClass` Int16,                                                              │
│    `OS` Int16,                                                                        │
│    `UserAgent` Int16,                                                                 │
│    `URL` String,                                                                      │
│)                                                                                      │
│ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/demo/hits_local', '{replica}')│
│ORDER BY (CounterID, EventDate, UserID, EventTime, WatchID)                            │
│SETTINGS index_granularity = 8192                                                      │
└───────────────────────────────────────────────────────────────────────────────────────┘
```

A few things to notice:

- The columns and types are exactly what `s3()` inferred from the Parquet
  file — no manual schema authored.
- `ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/demo/hits_local', '{replica}')`
  uses the `{shard}` and `{replica}` **macros**. The operator wires these per
  pod (e.g. shard `0`, replica `1` on `tests-clickhouse-0-1-0`), so all
  replicas of the same shard share a Keeper path and find each other for
  replication, while different shards stay isolated.
- `index_granularity = 8192` is the default block size for the sparse index —
  ClickHouse stores one index entry per 8,192 rows.

At this point you have an empty, sharded, replicated table, ready to load data
into via `INSERT INTO demo.hits SELECT * FROM s3(...)` or the parallel
`load.sh` script in `data-stacks/clickhouse-on-eks/examples/`.


## Query performance: choosing the right sort key

The remaining exercises assume the `demo.hits` table has been populated — for
example, by running `data-stacks/clickhouse-on-eks/examples/load.sh`, which
ships data from a local Parquet file in parallel into each shard. Once it's
loaded, the next two sections show how the sort key you picked in
[Step 3](#3-create-the-replicated-local-table) drives query performance.

Recall the sort key:

```text
ORDER BY (CounterID, EventDate, UserID, EventTime, WatchID)
```

Data on disk is physically sorted in that order, and ClickHouse builds a
**sparse primary-key index** with one entry per 8,192-row granule (the
`index_granularity` setting). Filters that line up with this layout get to
**skip granules** instead of scanning them.


### Pick interesting filter values

Find the most popular `EventDate` and `CounterID` so you have realistic values
to filter on:

```sql
SELECT EventDate, count() AS hits
FROM demo.hits
GROUP BY EventDate
ORDER BY hits DESC
LIMIT 1;
```

```sql
SELECT CounterID, count() AS hits
FROM demo.hits
GROUP BY CounterID
ORDER BY hits DESC
LIMIT 1;
```

For the dataset used here, `CounterID = 3922` and `EventDate = 15907` are good
picks.


### Fast: filter on the leading column of the sort key

`CounterID` is the **leftmost** column of `ORDER BY`, so the sparse index can
do a binary search directly on it.

```sql
EXPLAIN indexes = 1
SELECT
    count(),
    uniq(UserID) AS unique_users
FROM demo.hits
WHERE CounterID = '3922';
```

```text
    ┌─explain────────────────────────────────────────────────────────────────────┐
 1. │ Expression ((Project names + Projection))                                  │
 2. │   MergingAggregated                                                        │
 3. │     Union                                                                  │
 4. │       Aggregating                                                          │
 5. │         Expression (Before GROUP BY)                                       │
 6. │           Expression ((WHERE + Change column names to column identifiers)) │
 7. │             ReadFromMergeTree (demo.hits_local)                            │
 8. │             Indexes:                                                       │
 9. │               PrimaryKey                                                   │
10. │                 Keys:                                                      │
11. │                   CounterID                                                │
12. │                 Condition: (CounterID in [3922, 3922])                     │
13. │                 Parts: 8/8                                                 │
14. │                 Granules: 354/4109                                         │
15. │                 Search Algorithm: binary search                            │
16. │               Ranges: 8                                                    │
17. │       ReadFromRemote (Read from remote replica)                            │
    └────────────────────────────────────────────────────────────────────────────┘
```

Two things to notice in the plan:

- **`Search Algorithm: binary search`** — the engine can pinpoint the
  granules holding `CounterID = 3922` directly in the sparse index.
- **`Granules: 354/4109`** — only ~9% of the table's granules need to be
  read. The other ~91% are skipped entirely.


### Slow: filter on a non-leading column

`EventDate` is the **second** column in the sort key. Within each `CounterID`,
rows are sorted by `EventDate`, but across the table as a whole, `EventDate`
values are interleaved between many `CounterID` ranges.

```sql
EXPLAIN indexes = 1
SELECT
    count(),
    uniq(UserID) AS unique_users
FROM demo.hits
WHERE EventDate = '15907';
```

```text
    ┌─explain────────────────────────────────────────────────────────────────┐
 1. │ Expression ((Project names + Projection))                              │
 2. │   MergingAggregated                                                    │
 3. │     Union                                                              │
 4. │       AggregatingProjection                                            │
 5. │         Expression (Before GROUP BY)                                   │
 6. │           Filter ((WHERE + Change column names to column identifiers)) │
 7. │             ReadFromMergeTree (demo.hits_local)                        │
 8. │             Indexes:                                                   │
 9. │               PrimaryKey                                               │
10. │                 Keys:                                                  │
11. │                   EventDate                                            │
12. │                 Condition: (EventDate in [15907, 15907])               │
13. │                 Parts: 8/8                                             │
14. │                 Granules: 1542/4109                                    │
15. │                 Search Algorithm: generic exclusion search             │
16. │               Ranges: 446                                              │
17. │         ReadFromPreparedSource (_exact_count_projection)               │
18. │       ReadFromRemote (Read from remote replica)                        │
    └────────────────────────────────────────────────────────────────────────┘
```

Compare with the previous plan:

- **`Search Algorithm: generic exclusion search`** — the engine can't binary
  search; it walks the granules and skips ranges where the per-granule
  min/max stats prove `EventDate = 15907` cannot exist.
- **`Granules: 1542/4109`** — ~37% of granules read. Roughly **4× more work**
  than the `CounterID` filter.

Putting the row counts side by side:

```text
CounterID = '3922':   8.68 million rows, 121.31 MB  (3.87 GB/sec)
EventDate = '15907':  31.16 million rows, 345.54 MB (2.89 GB/sec)
```

The data is identical — only the filter column changed. The takeaway:

> **The order of columns in `ORDER BY` is the single biggest performance lever
> in MergeTree.** Put the columns you most commonly filter on first, in
> descending order of filter selectivity. Secondary filter patterns can be
> accelerated with [projections](https://clickhouse.com/docs/en/sql-reference/statements/alter/projection)
> or skip indexes — note the `_exact_count_projection` step that already
> appeared in the slow plan.


## Resilience: surviving a replica failure

The cluster runs **3 replicas per shard**. With `ReplicatedMergeTree`, every
replica holds an identical copy of the data, kept in sync via Keeper. The
`Distributed` table in front of them only needs **one healthy replica per
shard** to answer a query, so we can lose pods without downtime.


### See where the data lives on each replica

```sql
-- Diagnostic: ask every replica directly. With skip_unavailable_shards = 1
-- the query still completes if a replica is down.
SELECT
    hostName()           AS pod,
    getMacro('shard')    AS shard,
    getMacro('replica')  AS replica,
    count()
FROM clusterAllReplicas('default', demo.hits_local)
WHERE CounterID = 62
GROUP BY 1, 2, 3
ORDER BY 2, 3
SETTINGS skip_unavailable_shards = 1;
```

This bypasses the `Distributed` table and queries each `hits_local` replica
directly. You'll see **9 rows** (3 shards × 3 replicas) — and the per-shard
counts will be identical across replicas, since replicas hold the same data.

The `getMacro('shard')` / `getMacro('replica')` functions read the per-pod
macros that the operator injects into each ClickHouse config, which is also
how `ReplicatedMergeTree('/clickhouse/tables/{shard}/...', '{replica}')`
resolves at startup.


### Make replica selection deterministic

By default the `Distributed` engine load-balances across replicas. For
demonstration purposes, force it to always pick the first reachable replica so
you can see the failover happen:

```sql
SET load_balancing = 'in_order';

SELECT
    hostName()          AS pod,
    getMacro('shard')   AS shard,
    getMacro('replica') AS replica,
    count()             AS rows
FROM demo.hits
WHERE CounterID = 62
GROUP BY pod, shard, replica
ORDER BY shard ASC;
```

This time the query goes through `demo.hits` (the `Distributed` table), so it
picks **one replica per shard** — three rows, typically
`tests-clickhouse-{0,1,2}-0-0`. Note the response time (usually ~200 ms).


### Kill a pod and re-run

Open a second terminal and delete the replica that just served shard 2:

```bash
kubectl delete pod tests-clickhouse-2-0-0 -n clickhouse-tests
```

Re-run the same `SELECT ... FROM demo.hits` query. Two things should happen:

1. The query still returns in ~200 ms — the `Distributed` table fails over to
   the next replica in order, e.g. `tests-clickhouse-2-1-0`. The `pod` column
   in the result confirms that shard 2 is now being served by a different
   replica.
2. In the other terminal, the operator's `StatefulSet` is already recreating
   the deleted pod. Watch it:

   ```bash
   kubectl get pods -n clickhouse-tests -w
   ```


### Watch the replacement replica catch up

Once the pod is back, it has to replay any writes it missed via Keeper. You
can see this catch-up in `system.replicas`:

```sql
SELECT
    replica_name,
    absolute_delay,
    queue_size
FROM clusterAllReplicas('default', system.replicas)
WHERE table = 'hits_local';
```

- **`queue_size`** is the number of replication tasks still pending.
- **`absolute_delay`** is the lag (in seconds) behind the leader.

For a freshly restarted replica with no writes happening, both should drop to
zero quickly. While a heavy write workload is in flight, you'd see them shrink
as the replica catches up.


## Cleanup

This walkthrough deployed a `ClickHouseCluster`, a `KeeperCluster`, a
namespace, and a Kubernetes secret on top of the existing platform — but no
new AWS resources directly (Karpenter-provisioned nodes get torn down
automatically once the pods are gone). To remove everything this guide
created:

```bash
kubectl delete -f $CLICKHOUSE_DIR/examples/clickhouse-cluster.yaml
kubectl delete secret clickhouse-password -n clickhouse-tests
kubectl delete namespace clickhouse-tests
```

If you are completely finished with ClickHouse, you can destroy all the
infrastructure (EKS cluster, operator, Karpenter, ArgoCD, etc.) by following
the [Cleanup section](./infra.md#cleanup) of the infrastructure guide.
