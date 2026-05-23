---
sidebar_position: 8
sidebar_label: Valkey on EKS Benchmarks
---

# Valkey on EKS: Cluster Mode vs Replication Mode

## Introduction

[Valkey](https://valkey.io/) is the open-source, BSD-licensed fork of Redis maintained
under the Linux Foundation. The [Valkey on EKS data
stack](/data-on-eks/docs/datastacks/databases/valkey-on-eks) ships two
deployment topologies side by side, and the question that comes up first on every
migration call is *which one do I run, and what does each give me?* This page exists
to put real numbers — produced by `valkey-benchmark` against the live data-stack
running this site — behind that decision.

The two topologies, briefly:

- **Replication mode** — one writable primary plus N read replicas, all sharing the
  same keyspace. You get HA, read scale-out, and a simpler operational footprint at
  the cost of a single-node write ceiling. Deployed by the upstream
  [`valkey-io/valkey-helm`](https://github.com/valkey-io/valkey-helm) chart and is
  what `enable_valkey = true` provisions out of the box.
- **Cluster mode** — sharded across N primaries, each with its own replica set, with
  the 16384 hash slots distributed across primaries and a gossip protocol holding
  the topology together. You get linear write scale-out at the cost of a more
  complex client library (slot-aware) and the operational discipline that comes
  with running a distributed system. Deployed by the local chart at
  [`data-stacks/valkey-on-eks/examples/cluster-mode-helm-chart/`](https://github.com/awslabs/data-on-eks/tree/main/data-stacks/valkey-on-eks/examples/cluster-mode-helm-chart)
  via `examples/install-cluster-mode.sh`.

The benchmarks below were run on a clean cluster, on the canonical 256-byte SET /
GET / INCR workloads at 50 clients × pipeline 16, with the benchmark client
deployed as a sidecar pod on the same EKS cluster — out-of-cluster runs from a
laptop will skew the numbers heavily because of NAT / VPC-CNI / RTT effects.

## Hardware and topology

Both topologies were measured on identical hardware:

| Item                    | Value                                                          |
|-------------------------|----------------------------------------------------------------|
| EKS region              | `us-west-2`                                                    |
| Availability zones      | `us-west-2a`, `us-west-2b`, `us-west-2c`                       |
| Node instance type      | `r7g.large` (Graviton 3, 2 vCPU, 16 GiB)                       |
| Node provisioner        | Karpenter, on-demand only, AZ spread enforced                  |
| Pod size                | 1 vCPU request / 2 vCPU limit, 12 GiB request / 16 GiB limit   |
| Valkey image            | `docker.io/valkey/valkey:9.0.2`                                |
| Storage                 | EBS `gp3` PVC per pod, AOF + RDB enabled                       |
| Pod anti-affinity       | Soft per-node, **hard** AZ spread (`DoNotSchedule`)            |
| Benchmark client        | Same image, sidecar pod, 1 vCPU / 1 GiB                        |

**Replication mode**: 1 primary + 3 replicas, 4 pods total, primary in `us-west-2a`,
replicas in each of the three AZs.

**Cluster mode**: 3 primaries, each with 1 replica = 6 pods total. Every
primary↔replica pair lands in different AZs (verified via `verify-cluster.sh`
— see below).

## Workload

`valkey-benchmark` ships with the server image. We hold the workload constant and
flip only the deployment mode:

```text
-n 500000        # ops per test
-c 50            # parallel client connections
-P 16            # pipeline depth
-d 256           # value size in bytes
--threads 4      # client threads
-r 1000000       # randomize keys over 1M slot range
-t set,get,incr  # the canonical Valkey test trio
```

Pipelining at depth 16 is intentional. The point of this benchmark isn't to measure
the latency of a single SET — at 50 clients with `-P 1` you'll see roughly 80–120k
rps with sub-millisecond p50 — but to push enough work down the wire that the
**server CPU and the network NIC** become the bottleneck rather than client RTT,
which is what production traffic actually looks like.

## Running the benchmark

The two scripts live under `data-stacks/valkey-on-eks/examples/benchmark/`:

```bash
# 1. Sanity-check the cluster mode topology (cluster_state, slot coverage,
#    primary↔replica AZ pairing). Exits 1 on any failure.
./data-stacks/valkey-on-eks/examples/benchmark/verify-cluster.sh

# 2. Cluster-mode benchmark (default).
./data-stacks/valkey-on-eks/examples/benchmark/run-valkey-benchmark.sh \
    --mode cluster \
    --requests 500000 \
    --tests set,get,incr

# 3. Replication-mode benchmark.
./data-stacks/valkey-on-eks/examples/benchmark/run-valkey-benchmark.sh \
    --mode replication \
    --requests 500000 \
    --tests set,get,incr
```

The driver:

1. Reads the auth secret out of the target namespace (`valkey-cluster` or `valkey`).
2. Launches a one-shot runner pod with the **same image** as the server, on the
   Valkey NodePool, so `valkey-benchmark` and the cluster client are version-locked
   to the server. The runner pod is **not** scheduled on a Valkey data-plane node —
   running the benchmark client next to the server pod skews latency.
3. Executes `valkey-benchmark` with the requested workload, prints results.
4. Writes `summary.txt`, `raw.txt`, and `results.csv` to `/tmp/valkey-bench-<ts>/`.
5. For cluster mode only: prints per-primary `DBSIZE` and `valkey-cli --cluster
   check` output to confirm slot coverage and replica agreement.
6. Tears down the runner pod on exit (`--keep-runner` to preserve for debugging).

Useful flags:

| Flag                       | Default       | Notes                                          |
|----------------------------|---------------|------------------------------------------------|
| `--mode cluster\|replication` | `cluster`  | which deployment to target                     |
| `--requests N`             | `500000`      | ops per test                                   |
| `--clients N`              | `50`          | parallel client connections                    |
| `--pipeline N`             | `16`          | pipeline depth                                 |
| `--datasize N`             | `256`         | value size in bytes                            |
| `--threads N`              | `4`           | benchmark client threads                       |
| `--tests CSV`              | `set,get`     | any of `valkey-benchmark -t` test names        |
| `--keyspace-len N`         | `1000000`     | randomize keys over this slot range            |
| `--output DIR`             | `/tmp/...`    | where to write summary / raw / csv             |
| `--keep-runner`            | off           | leave the runner pod up after the benchmark    |
| `--workload-name STR`      | `<mode>`      | tag for CSV output / summary                   |

## Results

Both runs use exactly the workload and hardware described above. Numbers are
straight out of `valkey-benchmark` running inside the cluster. `valkey-benchmark`
caps reported throughput at 1,000,000 rps when the test completes faster than its
internal sampling window — any line that prints `1000000.00` should be read as
**"≥ 1.0 M rps, p50 is the real signal here"**.

### Cluster mode — 3 primaries + 3 replicas (6 pods)

```text
Test              Requests/s     p50 (ms)
----              ----------     --------
SET                  1000000        0.567
GET                  1000000        0.375
INCR                 1000000        0.495
```

Per-primary key distribution after the run (uniform random keys, 16384 slots
divided 5461/5461/5462 across 3 primaries):

```text
valkey-cluster-1: 350860 keys
valkey-cluster-2: 444289 keys
valkey-cluster-3: 420894 keys
```

`valkey-cli --cluster check` reported `[OK] All nodes agree about slots
configuration.` and all 16384 slots covered.

### Replication mode — 1 primary + 3 replicas (4 pods)

```text
Test              Requests/s     p50 (ms)
----              ----------     --------
SET                   399042        1.783
GET                  1000000        0.719
INCR                  487805        1.279
```

### Side-by-side

| Test | Cluster (3 primaries + 3 replicas, 6 pods) | Replication (1 primary + 3 replicas, 4 pods) | Cluster speedup    |
|------|---------------------------------------------|-----------------------------------------------|--------------------|
| SET  | ≥ 1,000,000 rps · p50 0.567 ms | 399,042 rps · p50 1.783 ms | ≥ 2.5× rps · 3.1× lower p50 |
| GET  | ≥ 1,000,000 rps · p50 0.375 ms | ≥ 1,000,000 rps · p50 0.719 ms | parity rps · 1.9× lower p50 |
| INCR | ≥ 1,000,000 rps · p50 0.495 ms | 487,805 rps · p50 1.279 ms | ≥ 2.0× rps · 2.6× lower p50 |

### Reading the numbers

A few things stand out, and they're exactly what the topology predicts:

- **Writes scale linearly with primaries.** Cluster mode at 3 primaries handles
  all three write tests (SET, INCR) above the 1.0 M reporter cap on `r7g.large`
  hardware. Replication mode pins every write to a single `r7g.large` and tops
  out around 400k SET / 488k INCR — almost exactly cluster's per-shard ceiling
  divided by 3. Add primaries, you get more write throughput; that's the entire
  point of cluster mode.
- **GET is fast in both, but cluster's p50 is half.** Replication mode reads here
  routed through the primary Service (default `valkey-io/valkey-helm` config — the
  primary is a write-back read endpoint, replicas are read-only). The primary's
  CPU is shared with all writes, so GET p50 lifts to 0.719 ms. Cluster mode spreads
  GETs across 3 primaries and lands at 0.375 ms p50.
- **Pipeline depth matters more than client count.** The same workload at `-P 1`
  drops to ~80k rps even on cluster mode — the cluster isn't slower, you're just
  paying RTT on every op. Production clients (`go-redis`, `lettuce`, `redis-py`)
  pipeline by default; build your benchmarks the same way.
- **The 1,000,000 rps cap is a tool artifact.** `valkey-benchmark` rounds up when
  the test finishes inside its sampling window. To see actual headroom, either
  raise `--requests` to 5,000,000 or drop pipeline to 8 and watch the rps spread
  open. p50 is the trustworthy signal at this throughput.

## When to use which

| You want…                                                | Choose       |
|----------------------------------------------------------|--------------|
| HA with a single keyspace and read scale-out             | Replication  |
| Cache-aside pattern, mostly GETs, single-region traffic  | Replication  |
| < 100 GiB working set, simple client libraries           | Replication  |
| Linear write throughput as you add nodes                 | Cluster      |
| Working set bigger than one node's RAM                   | Cluster      |
| Predictable per-shard latency under heavy write load     | Cluster      |
| Multi-AZ HA with strict cross-AZ pairing                 | Either; default config does this |

Replication mode is the right default for ~80% of Redis/Valkey workloads —
including everything that fits the cache-aside pattern. Cluster mode earns its
operational complexity when either (a) writes outgrow a single primary, or (b)
the working set outgrows a single node's RAM, or both.

## Verifying the cluster before benchmarking

The benchmark numbers are only meaningful if the cluster is healthy. The companion
script does the checks you'd otherwise run by hand:

```bash
$ ./data-stacks/valkey-on-eks/examples/benchmark/verify-cluster.sh

=== Pods ===
NAME               READY   STATUS    AGE   IP             NODE
valkey-cluster-0   2/2     Running   2h    100.64.132.98  ip-100-64-148-63...
valkey-cluster-1   2/2     Running   2h    100.66.17.50   ip-100-66-108-168...
valkey-cluster-2   2/2     Running   2h    100.65.39.96   ip-100-65-152-172...
valkey-cluster-3   2/2     Running   2h    100.66.232.178 ip-100-66-235-152...
valkey-cluster-4   2/2     Running   2h    100.64.239.114 ip-100-64-215-51...
valkey-cluster-5   2/2     Running   2h    100.65.13.114  ip-100-65-186-162...

=== cluster info ===
cluster_state:ok
cluster_slots_assigned:16384
cluster_slots_ok:16384
cluster_known_nodes:6
cluster_size:3

=== Topology + primary↔replica AZ pairing ===
PRIMARY  valkey-cluster-1     us-west-2c
  replica  valkey-cluster-3     us-west-2a    cross-AZ ✓
PRIMARY  valkey-cluster-2     us-west-2b
  replica  valkey-cluster-4     us-west-2c    cross-AZ ✓
PRIMARY  valkey-cluster-3     us-west-2a
  replica  valkey-cluster-5     us-west-2b    cross-AZ ✓

VERIFY: PASS — cluster_state=ok, all primary↔replica pairs are cross-AZ.
```

The verifier exits 0 only when:

- `cluster_state` is `ok`
- All 16384 slots are assigned and `ok`
- Every primary has at least one replica in a different AZ

If any of those fail, don't trust the benchmark output — fix the topology first.

## Tuning notes if you want to push harder

These are out of scope for the data stack defaults but worth knowing:

- **Network-optimized instances.** `r7gn.large`/`m7gn.large` have 4× the network
  bandwidth of `r7g.large`. The Karpenter NodePool already permits them; opt in
  per-shard via `tuning.networkOptimized: true` in the cluster-mode chart values.
- **Bigger pipeline.** `-P 32` or `-P 64` will keep more in flight, especially on
  network-optimized instances, but past ~16 the gains taper for small values.
- **Lower `repl-backlog-size` for replication mode.** The default 1 GiB backlog
  costs RAM that could be cache. Drop it if your replicas don't disconnect often.
- **`io-threads` on the server.** Valkey 8+ defaults to 1 I/O thread. On 8+ vCPU
  pods, set `io-threads 4` and watch SET rps lift 30–40% on a single shard.
- **Disable AOF for pure cache workloads.** AOF + `appendfsync everysec` costs
  about 5–10% of write throughput. The data stack default is on (durability >
  speed); flip it off in `values.yaml` if you treat the cluster as ephemeral.

## What this doesn't measure

This benchmark deliberately stays on the simple side:

- **No failure scenarios.** No primary kill, no AZ failure, no rolling restart.
  See the [cluster-mode operations
  guide](/data-on-eks/docs/datastacks/databases/valkey-on-eks/cluster-mode) for
  recovery time numbers from those.
- **No mixed read/write.** Run them serially. Real workloads almost always have a
  read-heavy steady state and a write-heavy backfill phase. Drive both with
  [memtier_benchmark](https://github.com/RedisLabs/memtier_benchmark) if you need
  arbitrary read/write ratios.
- **No long-running soak.** All tests finish in under 30 seconds. Memory
  fragmentation, AOF rewrite pauses, and replica `PSYNC` storms only show up
  past several hours.
- **No EC2 baseline.** If you want EKS-vs-EC2 numbers as part of a migration plan,
  see the [EC2 → EKS migration guide](/data-on-eks/docs/datastacks/databases/valkey-on-eks/ec2-migration)
  — same workload, run on both sides, captured in the same format.

## Reproducing on your cluster

The full reproduction loop, end-to-end, on a clean account:

```bash
# 1. Bring up the data stack (≈30 minutes; replication mode by default).
cd data-stacks/valkey-on-eks
./deploy.sh

# 2. Optionally add the cluster-mode chart on top (≈5 minutes).
export KUBECONFIG="$PWD/kubeconfig.yaml"
./examples/install-cluster-mode.sh

# 3. Verify the cluster topology.
./examples/benchmark/verify-cluster.sh

# 4. Run benchmarks against both modes.
./examples/benchmark/run-valkey-benchmark.sh --mode cluster      --output /tmp/bench-cluster
./examples/benchmark/run-valkey-benchmark.sh --mode replication  --output /tmp/bench-repl

# 5. Inspect / archive the CSVs.
cat /tmp/bench-cluster/results.csv /tmp/bench-repl/results.csv
```

`results.csv` is the artifact to keep — same schema across runs:

```csv
workload,mode,test,rps,p50_ms,clients,pipeline,datasize,timestamp
cluster,cluster,SET,1000000,0.567,50,16,256,20260522-231743
cluster,cluster,GET,1000000,0.375,50,16,256,20260522-231743
cluster,cluster,INCR,1000000,0.495,50,16,256,20260522-231743
```

Tear down the runner pod artifacts and any cluster-mode chart with
`./examples/uninstall-cluster-mode.sh`, then the full stack with `./cleanup.sh`.
