---
sidebar_position: 7
sidebar_label: Spark — Gluten + Velox vs Comet
---

import BarChart from '@site/src/components/Charts/BarChart';
import PieChart from '@site/src/components/Charts/PieChart';

## Apache Spark — Gluten + Velox vs DataFusion Comet Benchmarks

[Apache Spark](https://spark.apache.org/) has two leading native execution accelerators in active production use: [Apache Gluten](https://github.com/apache/incubator-gluten) with the [Velox](https://github.com/facebookincubator/velox) C++ backend, and [Apache DataFusion Comet](https://github.com/apache/datafusion-comet), built on the [Apache Arrow DataFusion](https://arrow.apache.org/datafusion/) Rust execution engine. Both offload Spark SQL operators to a vectorized native engine while keeping the Spark API and scheduler intact. They differ in implementation language (C++ vs Rust), shuffle manager, and the optimizer choices made by each plan rewriter.

This benchmark evaluates **Gluten + Velox v1.6.0** against **DataFusion Comet v0.16.0** on [Amazon EKS](https://aws.amazon.com/eks/) using the [TPC-DS](https://www.tpc.org/tpcds/) 3TB workload over Parquet, on identical hardware and Spark configuration.

:::info **TL;DR**
Our TPC-DS 3TB benchmark shows **Gluten + Velox v1.6.0 and DataFusion Comet v0.16.0 deliver similar overall runtime**: Gluten finishes 9% faster (2,239.93s vs 2,467.49s). Per-query results vary widely with join strategy and pipeline shape:

- Gluten + Velox is faster on large non-broadcast fact-table joins (up to **3.30× on q93**) by replacing Comet's `SortMergeJoin` with `ShuffledHashJoin`.
- Comet is faster on CPU-bound scan + aggregate pipelines and one large pre-aggregation join chain (**5.95× on q72**).
- 18 of 103 queries are 20%+ faster in Gluten Velox; 39 are 20%+ slower.
:::

## TPC-DS 3TB Benchmark Results

### Summary

Total runtime over the TPC-DS 3TB Parquet suite is within ~9% between **Gluten + Velox v1.6.0** and **DataFusion Comet v0.16.0**. The small headline gap is the result of large Gluten advantages on a few heavy queries cancelling out the time it loses on a larger number of medium-cost queries.

| Name | Completion Time (seconds) | Speedup |
|------|---------------------------|---------|
| Comet v0.16.0 | 2,467.49 | Baseline |
| Gluten + Velox v1.6.0 | 2,239.93 | **9% faster** |

### Benchmark Infrastructure

:::info Benchmark Methodology
Benchmarks ran sequentially on the same cluster to ensure identical hardware and eliminate resource contention. Both engines executed the full TPC-DS 3TB query suite on the same Parquet dataset.
:::

To ensure an apples-to-apples comparison, both Comet and Gluten + Velox jobs ran on identical hardware, storage, and data. Only the execution engine plugin and the related Spark settings differed.

#### Test Environment

| Component | Configuration |
|-----------|--------------|
| **EKS Cluster** | [Amazon EKS](https://aws.amazon.com/eks/) 1.34 |
| **Node Instance Type** | r8gd.12xlarge (Graviton4, 48 vCPUs, 384GB RAM, 1.8TB NVMe SSD) |
| **Node Group** | 12 nodes dedicated for benchmark workloads |
| **Executor Configuration** | 23 executors × 5 cores × 58GB RAM each |
| **Driver Configuration** | 5 cores × 20GB RAM |
| **Dataset** | [TPC-DS](https://www.tpc.org/tpcds/) 3TB (Parquet format) |
| **Storage** | [Amazon S3](https://aws.amazon.com/s3/) with optimized S3A connector |
| **Architecture** | aarch64 |

#### Spark Configuration Comparison

| Configuration | Comet v0.16.0 | Gluten + Velox v1.6.0 |
|---------------|---------------|-----------------------|
| **Spark Version** | 3.5.8 | 3.5.8 |
| **Java Runtime** | [OpenJDK](https://openjdk.org/) 17 (Eclipse Adoptium) | [OpenJDK](https://openjdk.org/) 17 (Eclipse Adoptium) |
| **Scala** | 2.12.18 | 2.12.18 |
| **Native Engine** | Rust + JVM hybrid ([DataFusion](https://arrow.apache.org/datafusion/)) | Native C++ ([Velox](https://github.com/facebookincubator/velox), ARM Neon) |
| **`spark.plugins`** | `org.apache.spark.CometPlugin` | `org.apache.gluten.GlutenPlugin` |
| **`spark.shuffle.manager`** | `CometShuffleManager` | `ColumnarShuffleManager` |
| **`spark.sql.extensions`** | `CometSparkSessionExtensions` | `GlutenSessionExtensions` |
| **Off-heap Memory** | 32GB enabled | 32GB enabled |
| **Per-task Off-heap Budget** | Managed by `CometPlugin` | 6.87 GB (5 task slots / executor) |
| **GC Tuning** | `-XX:+UseParallelGC`, `IHOP=70` | `-XX:+UseParallelGC`, `IHOP=70` |

#### Critical Comet-Specific Configurations

```yaml
# Comet plugin & shuffle manager
"spark.plugins": "org.apache.spark.CometPlugin"
"spark.shuffle.manager": "org.apache.spark.sql.comet.execution.shuffle.CometShuffleManager"

# Memory configuration
"spark.memory.offHeap.enabled": "true"
"spark.memory.offHeap.size": "32g"

# Comet execution settings
"spark.comet.exec.enabled": "true"
"spark.comet.exec.shuffle.enabled": "true"
"spark.comet.exec.shuffle.mode": "auto"
"spark.comet.explainFallback.enabled": "true"
"spark.comet.cast.allowIncompatible": "true"
"spark.comet.dppFallback.enabled": "true"
```

#### Critical Gluten + Velox-Specific Configurations

```yaml
# Gluten plugin & shuffle manager
"spark.plugins": "org.apache.gluten.GlutenPlugin"
"spark.shuffle.manager": "org.apache.spark.shuffle.sort.ColumnarShuffleManager"

# Memory configuration
"spark.memory.offHeap.enabled": "true"
"spark.memory.offHeap.size": "32g"
"spark.gluten.memory.offHeap.size.in.bytes": "34359738368"          # 32 GB executor off-heap
"spark.gluten.memory.task.offHeap.size.in.bytes": "6871947673"      # 6.87 GB per task off-heap
"spark.gluten.memory.conservative.task.offHeap.size.in.bytes": "3435973836"
"spark.gluten.memoryOverhead.size.in.bytes": "6442450944"
"spark.gluten.numTaskSlotsPerExecutor": "5"

# AQE cost evaluator (Velox-aware)
"spark.sql.adaptive.customCostEvaluatorClass": "org.apache.spark.sql.execution.adaptive.GlutenCostEvaluator"

# Java 17 reflective access required by Velox JNI
"spark.executor.extraJavaOptions": "--add-opens=java.base/sun.misc=ALL-UNNAMED --add-opens=java.base/sun.nio.ch=ALL-UNNAMED -Dio.netty.tryReflectionSetAccessible=true"
```

## Performance Results

### Overall Performance

<BarChart
  title="Total Runtime Comparison"
  data={{
    labels: ['Comet v0.16.0', 'Gluten + Velox v1.6.0'],
    datasets: [{
      label: 'Runtime (seconds)',
      data: [2467.49, 2239.93],
      backgroundColor: ['#16a085', '#2980b9'],
      borderColor: ['#117a65', '#1f618d'],
      borderWidth: 2
    }]
  }}
  options={{
    scales: {
      y: { title: { display: true, text: 'Runtime (seconds)' } }
    }
  }}
  height="300px"
/>

| Name | Completion Time (seconds) | Performance |
|------|---------------------------|-------------|
| Comet v0.16.0 | 2,467.49 | Baseline |
| Gluten + Velox v1.6.0 | 2,239.93 | **1.10×** (+9% time) |

### Performance Distribution

<PieChart
  title="Query Performance Distribution"
  type="doughnut"
  data={{
    labels: ['20%+ Gluten faster', '10-20% Gluten faster', 'Within ±10%', '10-20% Comet faster', '20%+ Comet faster'],
    datasets: [{
      data: [18, 13, 22, 11, 39],
      backgroundColor: ['#2980b9', '#5dade2', '#95a5a6', '#76d7c4', '#16a085'],
      borderWidth: 2,
      borderColor: '#ffffff'
    }]
  }}
/>

| Outcome | Query Count | Percentage |
|---|---|---|
| 20%+ Gluten faster | 18 | 17% |
| 10-20% Gluten faster | 13 | 13% |
| Within ±10% | 22 | 21% |
| 10-20% Comet faster | 11 | 11% |
| 20%+ Comet faster | 39 | 38% |

Although Gluten + Velox finishes only single digits faster overall, the per-query spread is wide. Comet finishes faster on a majority of queries, but the queries Gluten finishes faster on tend to be the heaviest in absolute runtime, so the time saved on a few large queries roughly cancels the time lost on many smaller ones.

### Top 10 Queries Where Gluten + Velox is Faster

<BarChart
  title="Top 10 Queries Where Gluten + Velox v1.6.0 is Faster Than Comet v0.16.0"
  data={{
    labels: ['q93', 'q50', 'q59', 'q39b', 'q23b', 'q23a', 'q29', 'q62', 'q5', 'q99'],
    datasets: [
      {
        label: '% Gluten faster',
        data: [70, 69, 60, 58, 53, 51, 46, 45, 42, 41],
        backgroundColor: '#2980b9',
        borderColor: '#1f618d',
        borderWidth: 1
      }
    ]
  }}
  options={{
    scales: {
      y: {
        beginAtZero: true,
        title: { display: true, text: '% Gluten faster' }
      },
      x: {
        title: { display: true, text: 'TPC-DS Queries' }
      }
    }
  }}
  height="400px"
/>

| Query | Comet v0.16.0 (s) | Gluten + Velox v1.6.0 (s) | Speedup |
|---|---|---|---|
| q93-v4.0 | 157.1 | 47.7 | **3.30×** (+70%) |
| q50-v4.0 | 107.5 | 33.2 | **3.24×** (+69%) |
| q59-v4.0 | 22.7 | 9.2 | **2.48×** (+60%) |
| q39b-v4.0 | 6.7 | 2.8 | **2.40×** (+58%) |
| q23b-v4.0 | 242.6 | 113.7 | **2.13×** (+53%) |
| q23a-v4.0 | 203.2 | 99.2 | **2.05×** (+51%) |
| q29-v4.0 | 26.5 | 14.2 | **1.87×** (+46%) |
| q62-v4.0 | 9.4 | 5.2 | **1.81×** (+45%) |
| q5-v4.0 | 19.7 | 11.5 | **1.72×** (+42%) |
| q99-v4.0 | 13.5 | 8.0 | **1.70×** (+41%) |

### Top 10 Queries Where Comet is Faster

<BarChart
  title="Top 10 Queries Where Comet v0.16.0 is Faster Than Gluten + Velox v1.6.0"
  data={{
    labels: ['q72', 'q27', 'q76', 'q13', 'q77', 'q30', 'q95', 'q18', 'q68', 'q48'],
    datasets: [
      {
        label: '% Comet faster',
        data: [83, 43, 41, 39, 38, 38, 35, 34, 33, 32],
        backgroundColor: '#16a085',
        borderColor: '#117a65',
        borderWidth: 1
      }
    ]
  }}
  options={{
    scales: {
      y: {
        beginAtZero: true,
        title: { display: true, text: '% Comet faster' }
      },
      x: {
        title: { display: true, text: 'TPC-DS Queries' }
      }
    }
  }}
  height="400px"
/>

| Query | Comet v0.16.0 (s) | Gluten + Velox v1.6.0 (s) | Speedup |
|---|---|---|---|
| q72-v4.0 | 32.5 | 193.5 | **5.95×** (+83%) |
| q27-v4.0 | 5.6 | 9.9 | **1.77×** (+43%) |
| q76-v4.0 | 35.9 | 61.2 | **1.70×** (+41%) |
| q13-v4.0 | 7.3 | 11.9 | **1.63×** (+39%) |
| q77-v4.0 | 2.1 | 3.4 | **1.62×** (+38%) |
| q30-v4.0 | 8.8 | 14.2 | **1.61×** (+38%) |
| q95-v4.0 | 69.2 | 106.7 | **1.54×** (+35%) |
| q18-v4.0 | 10.1 | 15.3 | **1.51×** (+34%) |
| q68-v4.0 | 4.3 | 6.4 | **1.49×** (+33%) |
| q48-v4.0 | 5.3 | 7.8 | **1.47×** (+32%) |

### Aggregate Workload Characteristics

Aggregate metrics across the full TPC-DS 3TB suite:

| Metric | Comet v0.16.0 | Gluten + Velox v1.6.0 | Delta |
|--------|---------------|------------------------|-------|
| Executors / Total Cores | 23 / 115 | 23 / 115 | identical |
| Max Memory | 996.5 GB | 996.5 GB | identical |
| Total Jobs | 6,192 | 6,139 | -53 |
| Total Stages | 9,170 | 9,110 | -60 |
| Total Tasks | 4,846,696 | 4,663,336 | -183,360 |
| Input | 14.4 TB | 15.0 TB | +614.9 GB |
| Shuffle Read | 2.5 TB | 8.7 TB | +6.2 TB ⚠ |
| Shuffle Write | 6.9 TB | 7.0 TB | +95.8 GB |
| Spill (Disk) | 0 B | 19.8 GB | +19.8 GB |
| GC Time | 6m 27.1s | 26.9s | **-6m 0.2s (14× less)** |

Two caveats apply to the table above:

- **Shuffle-read divergence is largely a metric artifact.** The +6.2 TB shuffle-read delta against an essentially identical +95.8 GB shuffle-write delta is dominated by `CometShuffleManager` not always incrementing Spark's standard shuffle-read counters for native columnar shuffle (visible at the stage level on q93, q72, and q76 where Comet writes are correctly recorded but reads register as 0 B). Gluten's `ColumnarShuffleManager` records actual byte volumes. The two engines are not actually moving 3× different shuffle volumes.
- **Off-heap memory accounting is asymmetric.** Gluten consistently reports 80–264 MB peak per-task exec memory in dominant stages; Comet reports 0 B in the same metric because its native-side allocations are not surfaced through Spark's `peakExecutionMemory` counter. Direct memory comparison from the History Server alone is not possible.

The 14× GC reduction in Gluten reflects Velox's off-heap compute pipeline: when the dominant work runs in native code, JVM allocations during query execution drop sharply. The 19.8 GB Gluten spill is concentrated outside the top-5/bottom-5 queries; none of the queries analyzed in detail below spilled in either engine.

### Notes on Performance Differences

:::note Analysis tooling
The per-query plan diffs and stage-level metrics in this section were produced with [Kiro](https://kiro.dev) using the [`mcp-apache-spark-history-server`](https://github.com/kubeflow/mcp-apache-spark-history-server) MCP server, which exposes Spark History Server data to AI agents over the Model Context Protocol.
:::

#### Queries where Gluten + Velox is faster

**q93-v4.0 — Gluten Velox 3.30× faster (157.1s → 47.7s)**

- The single shuffled-join stage drops from 2m0.986s to 12.855s (200 tasks each); per-task p50 drops from 58.336s to 6.523s (~9× faster). All upstream and downstream stages are within ~5% between engines, with no spill, no GC, and no skew.
- Plan diff: `CometSortMergeJoin` + 2× `CometSort` → `ShuffledHashJoinExecTransformer`. The 8.64B-row `store_sales` side and 12.4M-row `store_returns` side feed a sort-merge join in Comet vs a hash-build/probe in Gluten.
- **Root cause:** Comet must fully sort the 293 GiB / 8.64B-row shuffled `store_sales` partitions before merging. Gluten builds a small ~240 MB hash table on the `store_returns` side and streams the larger side through it.

**q50-v4.0 — Gluten Velox 3.24× faster (107.5s → 33.2s)**

- Probe-side join stage drops from 1m22.2s to 9.764s (200 tasks each); per-task p50 40.306s → 4.967s (8.1× faster), with no spill and only 10–30 ms GC.
- Build-side scans are within 1 second of each other (`store_sales` 22.211s vs 21.591s; `store_returns` 21.221s vs 21.284s). The +6,791 task delta is almost entirely from added `WholeStageCodegenTransformer` / `InputIteratorTransformer` / `VeloxResizeBatches` wrappers around the same 200-partition shuffles.
- **Root cause:** same SMJ → SHJ swap as q93. Comet emits `CometSortMergeJoin` with 2× `CometSort`; Gluten emits `ShuffledHashJoinExecTransformer` with no sort.

**q59-v4.0 — Gluten Velox 2.48× faster (22.7s → 9.2s)**

- Two `store_sales` scan stages dominate: combined wall time 31.85s → 12.57s. Per-stage input drops from **18.9 GB / 8.25B records → 4.1 GB / 1.69B records** (4.6× fewer bytes, 4.9× fewer records) at p50 task 299–344 ms vs 40–56 ms.
- Same 16 stages, same 3,193-task partitioning, same shuffle volume (~150 MB) on both engines. The divergence is upstream at the Parquet readers, not in the shuffle pipeline.
- Secondary contributor: Comet's single non-broadcast join is `CometSortMergeJoin` + 2× `CometSort`; Gluten swaps to `ShuffledHashJoinExecTransformer`.
- **Root cause:** Velox's Parquet scan returns 4.6× less data for the same logical output (likely tighter filter/predicate pushdown or vectorized pruning), and the SMJ → SHJ swap removes the post-shuffle sort step.

**q39b-v4.0 — Gluten Velox 2.40× faster (6.7s → 2.8s)**

- Two `inventory` scan stages each finish ~2.9–3.0s faster. The straggler-task delta of -2.93s/-3.03s maps 1:1 onto the -3.339s wall-clock speedup.
- No plan-shape change in the join graph (7 BHJs, 1 sort, partial+final agg are operator-1:1); zero spill, zero GC, identical input bytes (181.7 vs 183.5 MB).
- Secondary: Gluten emits 24% less shuffle write per scan stage (45.6 MB vs 59.9 MB peak), reducing downstream shuffle work.
- **Root cause:** per-task compute throughput on the broadcast-join + partial-aggregate chain executed by the single non-empty `inventory` partition. Velox's vectorized pipeline runs the scan → 4× BHJ → partial agg → shuffle-write at ~2.85× higher throughput.

**q23b-v4.0 — Gluten Velox 2.13× faster (242.6s → 113.7s)**

- Total stage time: 6m 49.6s → 3m 54.4s (-2m 55.1s). Dominant 200-task reducer pair: Comet ingests 50.9 GB / 8.09B records at p50 17.7s/task; Gluten ingests 118.6 GB / 16.63B records at p50 8.6s/task. That is 2.3× the bytes and 2.1× the rows in 0.49× the runtime (~4.7× per-byte throughput).
- Operator counts: **15 `CometSortMergeJoin` + 26 `CometSort` → 15 `ShuffledHashJoinExecTransformer` + 0 sort transformers** (Gluten has no sort operators in the entire plan).
- 0 B spill in both runs; GC ≤ 649 ms total. The 2× speedup is pure compute despite Gluten executing 48 stages / 32,137 tasks vs Comet's 19 / 10,545.
- **Root cause:** Comet's optimizer picks SMJ for all 15 large fact-fact and fact-dim joins, forcing 26 explicit sorts on the shuffled inputs. Gluten replaces all 15 with SHJ inside Velox vectorized pipelines, at substantially higher per-task throughput on the dominant reducers.

#### Queries where Comet is faster

**q72-v4.0 — Comet 5.95× faster (32.5s → 193.5s in Gluten)**

- **One stage explains 98% of the gap.** Comet's dominant stage runs in 21.16s; the matching Gluten stage takes 3m 3.4s. Both have 200 uniform tasks producing identical output (1.4 GB / 28,523,265 records). Per-task p50: **7.635s → 1m 25.332s (11.2× slower in Gluten Velox)**, with no skew (p75/p25 = 1.06×, max/p50 = 1.11×).
- Per-record throughput at p50: Gluten ~59,300 records/s/task vs Comet ~666,000 records/s/task. No spill, Gluten 0 ms GC in this stage, peak exec memory uniform 248–264 MB (well below the 6.87 GB task budget).
- Plan diff: 2× `SortMergeJoin` + 1× `CometSortMergeJoin` (Comet) → 3× `ShuffledHashJoinExecTransformer` (Gluten, **zero sort operators in the plan**). Sum of all other stages: Comet ≈ 32s, Gluten ≈ 26s; Gluten is faster on every stage except this one.
- Secondary: Gluten reads +5.5 GB more raw Parquet (`catalog_sales` 657.9 MB → 3.6 GB and `inventory` 2.6 GB → 5.1 GB for identical record counts), adding ~3s.
- **Root cause:** the opposite of q93/q50/q23b. For this 1B-row pipeline carrying through the join chain, Comet's SortMergeJoin path runs ~11× faster per task than Velox's ShuffledHashJoin pipeline within a fully columnar Velox stage.

**q27-v4.0 — Comet 1.78× faster (5.6s → 9.9s in Gluten)**

- **One probe-side stage owns the gap.** Comet's stage runs in 4.682s (631 tasks, p50 712 ms); the Gluten stage runs in 8.695s (631 tasks, p50 1.398s). Per-task p50 +686 ms (1.96× slower in Gluten Velox) on identical 1,632,143,161 input records. The stage delta of +4.013s ≈ the entire query delta of +4.061s.
- Same 1,388 tasks, same scan/join graph. The +664 MB input and +25.7 MB shuffle deltas (3% / 16%) are too small to explain a 1.96× per-task slowdown.
- Plan rewrite: single `CometHashAggregate` → `Flushable + Regular HashAggregateExecTransformer` split (+1 stage, 10 vs 9). Gluten reports 224 MB peak exec memory per task that Comet does not surface.
- **Root cause:** Velox's columnar pipeline for scan + 4× BroadcastHashJoin + Expand + partial-aggregate is ~2× slower per task than Comet's fused `CometHashAggregate` over the same data. The partial/final aggregate split, +4 extra `ProjectExecTransformer` nodes, and `VeloxResizeBatches`/`InputIteratorTransformer` glue accompany the slowdown.

**q76-v4.0 — Comet 1.69× faster (35.9s → 61.2s in Gluten)**

- Per-task slowdown across the 3 large scan + partial-agg + shuffle-write stages: p50 **496 → 758 ms (+53%)** on `store_sales` (3,193 tasks), **521 → 725 ms (+39%)** on `web_sales` (1,380 tasks), **413 → 541 ms (+31%)** on `catalog_sales` (2,898 tasks). Combined +29.6s of stage time on identical input bytes.
- **Final-agg stage straggler:** Comet runs 600 AQE-coalesced tasks in 1.202s; Gluten coalesces to only 157 tasks and is dominated by a single straggler with task quantiles p25/p50/p75/**max = 660/747/771/13,906 ms** (max is 18× p75). Adds +13.4s.
- Total stage time 1m 41.7s → 2m 37.5s (+55.8s); spill 0 / 0; GC 391 ms vs 25 ms (not the cost). Plan grew from 40 to 73 nodes (+33).
- **Root cause:** two compounding factors. (1) Per-task slowdown on the heavier columnar partial-aggregation pipeline. (2) AQE under-coalescing of the union-shuffle for the final aggregate, producing a single 13.9s straggler.

**q13-v4.0 — Comet 1.61× faster (7.3s → 11.9s in Gluten)**

- Dominant `store_sales` stage: 635 tasks, identical 1,641,110,765 records, 50.2 vs 50.7 MB at p50 input, p50 task **894 ms → 1.458 s (+63%)**. Per-task throughput drops from ~56 MB/s to ~35 MB/s. The stage delta of +3.383s accounts for **78% of the +4.340s gap**.
- The remaining ~0.8s comes from a small SMJ → SHJ flip on the `store_sales × customer_demographics` join, which adds an extra shuffle cluster.
- Plan grew from 66 to 85 nodes; +7 stages, +1,447 tasks (817 → 2,264) for the same query, driven by aggregate split, +5 `VeloxResizeBatches`, +9 `InputIteratorTransformer`. Total shuffle read is only 84.6 MB, so data movement is not the cost.
- **Root cause:** per-task scan + filter + partial-aggregate over `store_sales` is ~1.6× slower in Velox even with 152–160 MB peak exec memory in use. Small structural plan overhead (SMJ → SHJ tail) adds ~20% on top.

**q77-v4.0 — Comet 1.61× faster (2.0s → 3.2s in Gluten)**

- The 3 dominant scan-side feeder stages are each ~1.5–2.05× slower in Gluten: `store_sales` p50 **443 → 921 ms (+108%)** at 184M rows; `catalog_sales` p50 188 → 259 ms; `web_sales` p50 112 → 96 ms but max 603 → 1,028 ms. The `store_sales` stage delta alone (+0.730s) explains most of the +1.186s query gap.
- Gluten's total executor runtime across all 14 stages is 125.8s → 194.8s (+69s of CPU, +55%) on the same 2.8 GB input and ~3× *less* shuffle (17.8 MB → 6.2 MB).
- Plan grew from 104 to 154 nodes (+48%): 13 → 28 `ProjectExecTransformer` nodes, single `CometHashAggregate` → `Flushable + Regular` split, +21 `InputIteratorTransformer`, +7 `VeloxResizeBatches`, +17 `WholeStageCodegenTransformer` blocks.
- **Root cause:** CPU-bound scan/agg pipeline with negligible shuffle and zero spill. The additional per-batch operator overhead in Velox's WSCG transformer chain produces a ~2× per-task slowdown that cannot be amortized over data movement.

#### Cross-Query Patterns

Six recurring root-cause categories explain the per-query divergence:

**1. Sort-Merge Join → Shuffled Hash Join on large fact ⋈ moderate side — Gluten + Velox is faster**

Queries: q93, q50, q23a, q23b (and partially q59 for the single non-broadcast join). Comet's optimizer plans the largest non-broadcast joins as `CometSortMergeJoin` + `CometSort` on the shuffled inputs; Gluten plans the same joins as `ShuffledHashJoinExecTransformer` with no sort step. When the build side is small enough to hash but the probe side is in the billions of rows, eliminating the explicit sort of the shuffled probe collapses one stage from ~17–60s/task to ~5–9s/task (5–9× per-task speedup). Across q93, q50, and q23b this single algorithmic difference accounts for most of the runtime advantage in Gluten's favor.

**2. Velox per-task scan-side input reduction — Gluten + Velox is faster**

Queries: q59. For the same logical `store_sales` scan, Velox's `FileSourceScanExecTransformer` returns 4.6× fewer bytes (4.1 GB vs 18.9 GB) and 4.9× fewer records (1.69B vs 8.25B) per stage with identical 3,193-task partitioning. Same shuffle volume downstream, same plan shape. The cause is upstream in Parquet read, likely tighter predicate or runtime-filter pushdown, but the metrics surfaced by the History Server do not pinpoint the exact mechanism.

**3. Velox per-task throughput on broadcast-join + partial-aggregate chain — Gluten + Velox is faster**

Queries: q39b. With operator-equivalent plans (no SMJ → SHJ flip, same 7 BHJs), Velox runs the scan → 4× BHJ → partial-agg → shuffle-write pipeline at ~2.85× higher throughput on the single straggler task. No GC, no spill, identical input bytes. The gap comes from vectorized compute throughput.

**4. Shuffled Hash Join → Sort-Merge Join inverse on large pre-aggregation chain — Comet is faster**

Queries: q72. Comet plans the three non-broadcast joins as `SortMergeJoin` (2 plain Spark + 1 `CometSortMergeJoin`); Gluten plans them as `ShuffledHashJoinExecTransformer`. Within Velox's fully columnar pipeline (18 `WholeStageCodegenTransformer`, 8 `VeloxResizeBatches`), the SHJ chain processes records at ~59K records/s/task while Comet's SMJ pipeline runs at ~666K records/s/task. The 11× per-task slowdown materializes uniformly across all 200 tasks and accounts for ~98% of the runtime advantage in Comet's favor on this query. The same algorithmic choice that helps Gluten on q93/q50/q23b is the largest single cost on q72.

**5. Velox per-task scan + aggregate slowdown vs Comet — Comet is faster**

Queries: q27, q13, q77, q76 (component 1). A consistent pattern across four queries where Comet is faster: identical input data per task (same record counts, ±3% bytes), but Velox's per-task wall time on `FileSourceScanExecTransformer` + `FilterExecTransformer` + `BroadcastHashJoinExecTransformer` chain + `FlushableHashAggregateExecTransformer` is **1.5–2.0× slower per task** than Comet's fused `CometNativeScan` + `CometFilter` + `CometBroadcastHashJoin` + `CometHashAggregate`. Common accompanying plan changes:

- Single `CometHashAggregate` → split `Flushable + Regular HashAggregate` across an extra shuffle (+1 stage)
- 4–15 extra `ProjectExecTransformer` nodes
- `VeloxResizeBatches`, `InputIteratorTransformer`, `WholeStageCodegenTransformer` glue (typically +20–50 plan nodes for the same query)

Data movement is not the cost: q13, q27, and q77 each move &lt;100 MB of total shuffle, and q76 writes *less* shuffle in Gluten (1.6 GB vs 2.4 GB). The slowdown is CPU-bound in the columnar transformer chain.

**6. AQE coalesce under-partitioning + skew — Comet is faster (partial)**

Queries: q76 (component 2). Gluten's final-aggregation stage coalesces to 157 tasks; Comet's equivalent runs 600 AQE-coalesced tasks. The full 1.6 GB of shuffle is read with task-quantile distribution **p25/p50/p75/max = 660/747/771/13,906 ms**: a single straggler runs 18× p75 and dominates the 14.6s stage. Comet pipelines the same union into the post-shuffle aggregate without registering a shuffle read at all (writes 2.4 GB upstream → reads 0 B at the consuming stage), avoiding the coalesce path entirely. Adds +13.4s of the +26.7s q76 gap.

#### Summary

The largest plan-level driver across these queries is join-strategy choice. In the top 5 queries where Gluten + Velox is faster, Gluten replaced a Comet `(Comet)SortMergeJoin` + sort feeders with a `ShuffledHashJoinExecTransformer`, and that replacement accounted for most of the runtime difference. The same strategy choice produces the largest gap in Comet's favor on q72. Comet's optimizer prefers SMJ; Gluten's prefers SHJ. Which engine completes a given query in less time depends on whether the SHJ build-side fits comfortably in memory and whether the per-record SHJ-probe rate is competitive with the SMJ merge rate for that plan shape.

A second source of overhead in Gluten Velox is aggregate split across an extra shuffle. In every Gluten plan inspected, a single `CometHashAggregate` is replaced by a `FlushableHashAggregateExecTransformer` (partial) + `RegularHashAggregateExecTransformer` (final) split across an additional `ColumnarExchange`/`AQEShuffleRead` boundary. This adds +1 stage and a small fixed cost per query. Combined with the per-task scan/aggregate slowdown observed in q27, q76, and q77, this is what makes Comet the faster engine on those queries.

Comet's total GC time (6m 27s vs 26.9s for Gluten) is concentrated in JVM-heavy stages that Velox bypasses. Per-query, the GC reductions are most visible on stages where Comet had heavy stage-level GC. On queries where Comet is faster, however, the per-record cost differential is larger than the GC savings: Velox removes JVM GC, but the columnar pipeline costs more per record on those plan shapes.

📊 **[View complete benchmark results and detailed per-query analysis →](https://github.com/awslabs/data-on-eks/tree/main/data-stacks/spark-on-eks/benchmarks/datafusion-comet-velox-gluten)**
