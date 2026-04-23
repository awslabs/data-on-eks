---
sidebar_position: 7
sidebar_label: StarRocks Shared-Data vs Shared-Nothing
---

import BarChart from '@site/src/components/Charts/BarChart';
import PieChart from '@site/src/components/Charts/PieChart';

# StarRocks on EKS: Shared-Data vs Shared-Nothing

## Introduction

[StarRocks](https://starrocks.io/) is a high-performance analytical database that supports two deployment architectures on Kubernetes. Which architecture you choose has major implications for cost, elasticity, and performance — so this benchmark gives you hard numbers to make an informed decision.

### Why This Benchmark Matters

When you're building an analytics platform on EKS, you face a fundamental storage architecture choice:

- **Shared-Data (cloud-native)**: Stateless Compute Nodes (CN) read from S3 with local NVMe SSD cache. Storage and compute scale independently. Lower storage cost, higher elasticity.
- **Shared-Nothing (traditional)**: Backend Nodes (BE) store data on local EBS volumes and perform both storage and compute. Data locality, but tighter coupling.

Both claim to deliver excellent OLAP performance, but the trade-offs aren't obvious from documentation alone. Common questions we answer here:

- Does S3 with NVMe cache match the speed of local EBS?
- Is the shared-data model worth the S3 latency for interactive analytics?
- What's the CPU/memory footprint difference under identical workloads?
- Which architecture gives better price-performance on AWS?

This benchmark answers these questions by running the **TPC-DS 1TB decision support benchmark** against both architectures on **identical compute hardware**, isolating storage as the only variable.

### Executive Summary (TL;DR)

<div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '1rem', marginBottom: '2rem' }}>
  <div style={{ background: '#e8f5e9', padding: '1.25rem', borderRadius: '8px', borderLeft: '4px solid #27ae60' }}>
    <h4 style={{ marginTop: 0, color: '#27ae60' }}>Shared-Nothing Wins on Raw Speed</h4>
    <p style={{ marginBottom: 0 }}>EBS-backed BE delivers <strong>178.6s total, 1,822ms mean</strong> across 98 queries — <strong>7.8% faster</strong> than shared-data. Local EBS (6000 IOPS) has lower and more predictable latency than S3+NVMe cache for TPC-DS at this scale.</p>
  </div>
  <div style={{ background: '#e3f2fd', padding: '1.25rem', borderRadius: '8px', borderLeft: '4px solid #2196f3' }}>
    <h4 style={{ marginTop: 0, color: '#2196f3' }}>Shared-Data Wins on Flexibility</h4>
    <p style={{ marginBottom: 0 }}>S3 + NVMe cache delivers <strong>193.8s total, 1,977ms mean</strong> — very competitive for cloud-native architecture. Unlimited storage, second-scale elasticity (CN can scale 0→N), and ~4x lower storage cost at scale.</p>
  </div>
</div>

**Key findings:**

- **Compute is identical**: Both clusters use 3× r8g.8xlarge / r8gd.8xlarge nodes (96 vCPU / 768 GiB total). The ONLY variable is storage architecture.
- **Performance gap is small (~8%)**: Shared-nothing is faster, but not dramatically so. S3 + NVMe cache is surprisingly competitive once cache is warm.
- **NVMe cache is critical** for shared-data: cold reads are 10-12x slower than warm. First iteration hits S3; iterations 2-3 hit local NVMe.
- **q23 is the worst case for shared-data**: 35.9s vs q23 is one of the slowest queries in both architectures (cross-joins on large fact tables).
- **q95 times out on both**: Same query failure pattern — not a storage issue but a query planner/optimizer issue.
- **BE memory baseline is high**: Shared-nothing BE uses ~85 GiB baseline even idle (page cache, tablet metadata). Size accordingly.

**Use shared-data when**: unpredictable workloads, need elasticity, large datasets (&gt;10TB), multi-tenant, cost-sensitive storage.

**Use shared-nothing when**: predictable workloads, consistent low latency required, smaller datasets (&lt;10TB), dedicated clusters.

## Benchmark Configuration

### Test Environment

| Component | Configuration |
|-----------|---------------|
| **EKS Cluster** | Amazon EKS v1.34.6 |
| **Region** | us-east-1 |
| **StarRocks Version** | 3.5-latest |
| **Operator Version** | v1.11.3 (deployed via ArgoCD) |
| **Dataset** | [TPC-DS](https://www.tpc.org/tpcds/) Scale Factor 1000 (~1TB raw) |
| **Queries** | All 99 standard TPC-DS queries |
| **Iterations** | 3 per query — reports min / avg / max |
| **Query Timeout** | 600 seconds |

### Cluster Specifications

Both clusters have **identical compute resources** — the only variable is storage. This isolates the impact of storage architecture.

<div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '1rem', marginBottom: '1.5rem' }}>

<div style={{ background: '#f8f9fa', padding: '1.25rem', borderRadius: '8px', border: '2px solid #3498db' }}>

#### Shared-Data (CN + S3)

| | |
|---|---|
| **FE** | 3× m6g.2xlarge (8 vCPU, 32 GiB) |
| **CN** | 3× **r8gd.8xlarge** (32 vCPU, 256 GiB) |
| **CN requests** | 28 vCPU, 220 GiB |
| **CN limits** | 31 vCPU, 240 GiB |
| **Data storage** | **S3** (unlimited) |
| **Cache** | **1.9 TB NVMe SSD** per CN (RAID0) |
| **FE metadata** | 100Gi gp3 EBS |

</div>

<div style={{ background: '#f8f9fa', padding: '1.25rem', borderRadius: '8px', border: '2px solid #e67e22' }}>

#### Shared-Nothing (BE + EBS)

| | |
|---|---|
| **FE** | 3× m6g.2xlarge (8 vCPU, 32 GiB) |
| **BE** | 3× **r8g.8xlarge** (32 vCPU, 256 GiB) |
| **BE requests** | 28 vCPU, 220 GiB |
| **BE limits** | 31 vCPU, 240 GiB |
| **Data storage** | **EBS gp3-starrocks** |
| **EBS spec** | 500Gi × 3, **6000 IOPS, 250 MB/s** |
| **FE metadata** | 100Gi gp3 EBS |

</div>

</div>

### Why These Instance Types?

StarRocks recommends a **minimum 1:4 vCPU:GB memory ratio** for compute nodes. The `r` family (memory-optimized Graviton) delivers 1:8 — exceeding the minimum with headroom for:

- **Vectorized hash joins** and aggregation state (lives in RAM)
- **Data cache page cache** on the CN side (NVMe-backed on r8gd)
- **Bloom filters, dictionary caches, tablet metadata** (always in memory)

The `d` suffix (`r8gd`) adds local NVMe SSD — essential for shared-data CN cache. The shared-nothing BE uses `r8g` without local NVMe since data persistence lives on EBS PVCs.

<details>
<summary><strong>Why not compute-optimized (c7g, c8g)?</strong></summary>

Compute-optimized instances have a 1:2 vCPU:GB ratio — below StarRocks' minimum 1:4 recommendation. You'll see OOM kills on big joins long before you run out of CPU. We tested this early and observed CN pods failing to schedule with 128 GiB memory requests on c-family instances.
</details>

<details>
<summary><strong>Why not network-optimized (r6in, m6in)?</strong></summary>

Network-optimized instances (up to 200 Gbps) are a tempting trap for shared-storage architectures. In practice, once the Data Cache hit rate is &gt;80% (typical in production), the bottleneck shifts from network to local NVMe IOPS and memory. The extra network bandwidth costs 15-25% more for throughput you won't use after warmup.
</details>

<details>
<summary><strong>Why not storage-optimized (i4i, im4gn)?</strong></summary>

i4i/im4gn have excellent local NVMe but the vCPU:GB ratio is 1:8 with too much memory — you over-provision for StarRocks' needs. These instances make more sense for ClickHouse-style workloads.
</details>

### Storage Architecture Deep Dive

| Dimension | Shared-Data (CN + S3) | Shared-Nothing (BE + EBS) |
|-----------|----------------------|---------------------------|
| **Primary storage cost** | S3 Standard (~$0.023/GB/mo) | EBS gp3 (~$0.08/GB/mo) |
| **Cache layer** | 1.9 TB NVMe (free with instance) | N/A |
| **Cold read latency** | 10-50ms (S3 GET) | 1-2ms (EBS gp3) |
| **Warm read latency** | ~0.1ms (NVMe cache hit) | 1-2ms (EBS gp3) |
| **Cache hit rate** | ~90% after warmup (TPC-DS) | 100% (all data is local) |
| **Storage IOPS** | NVMe: ~100K+ per node | EBS: 6,000 per volume |
| **Storage throughput** | NVMe: 2+ GB/s per node | EBS: 250 MB/s per volume |
| **Max storage size** | Unlimited (S3) | 500 GiB per BE (1.5TB total) |
| **Stateful** | No (CN is stateless, cache is ephemeral) | Yes (data on EBS PVCs) |
| **Elasticity** | Scale CN 0→N in seconds | Scale BE requires data rebalancing |
| **Data durability** | 99.999999999% (S3 11 nines) | 99.999% (EBS) |
| **Multi-AZ** | S3 cross-AZ by default | Requires explicit replication |

## Benchmark Methodology

### TPC-DS Table Format

Both clusters use **identical StarRocks native table DDL** — no external catalogs, no Iceberg, no Hive. Data is loaded directly into StarRocks managed tables so the benchmark measures pure StarRocks query execution.

All 24 TPC-DS tables use the **Duplicate Key** model — StarRocks' default table type optimized for append-heavy OLAP workloads:

- **Table type**: `duplicate key` (append-only, no primary key uniqueness)
- **Distribution**: `distributed by hash(<key>) buckets N` — data is sharded across buckets by hash of the join key
- **Replication**: `replication_num = 1` — single replica (no data redundancy for the benchmark)
- **Storage engine**: OLAP (columnar, sorted by duplicate key for range scans)

Example from `store_sales`:

```sql
create table store_sales (
    ss_sold_date_sk           integer,
    ss_item_sk                integer   not null,
    ss_ticket_number          bigint    not null,
    -- ... 20+ more columns ...
    ss_net_profit             decimal(7,2)
)
duplicate key (ss_sold_date_sk, ss_item_sk, ss_ticket_number)
distributed by hash(ss_item_sk, ss_ticket_number) buckets 261
properties("replication_num" = "1");
```

**Why Duplicate Key model?**

- **Best for immutable analytical data** (fact tables like store_sales) — TPC-DS loads append-only
- **Lower write amplification** than Primary Key model (no compaction for uniqueness)
- **Full columnar compression** with sort-by-key push-down
- **Matches StarRocks' own recommended TPC-DS schema**

The **key difference between the two clusters is WHERE the data is physically stored**:

- **Shared-Data**: Duplicate Key tables → S3 objects (managed by StarRocks starmgr)
- **Shared-Nothing**: Duplicate Key tables → EBS volumes on BE pods (local storage)

The SQL DDL is byte-for-byte identical. StarRocks abstracts the storage layer from the table definition.

### Data Generation

We used the standard TPC-DS `dsdgen` tool at scale factor 1000 (~1TB raw data):
- **Output**: 10,015 `.dat` files, ~911 GB total
- **Duration**: ~2 hours using 32 parallel `dsdgen` workers on a Graviton r6g.8xlarge
- **Storage**: ReadWriteOnce PVC (1 TiB gp3), shared across both loaders

### Data Loading

Both clusters were loaded from the same PVC using StarRocks `_stream_load` HTTP API:
- **Loading target**: ~12 GiB columnar-compressed in S3 (shared-data) / ~12 GiB on EBS (shared-nothing)
- **Compression ratio**: ~3-5x vs raw text
- **Loading duration**: 5-7 hours per cluster (single-threaded via curl)
- **Data parity**: Row counts verified near-identical between both clusters (store_sales: 2.75B rows, catalog_sales: ~1.4-1.5B, web_sales: 720M)

### Query Execution

Each benchmark run executes all 99 TPC-DS queries for **3 iterations**:
- **Iteration 1**: Cold cache (CN reads from S3, BE reads from EBS for first time)
- **Iteration 2**: Warm cache (NVMe for CN, page cache for BE)
- **Iteration 3**: Fully warm

Results report **min / avg / max** per query across iterations. The avg is used as the representative query time.

## Results

### Overall Runtime Comparison

<BarChart
  title="TPC-DS 1TB Total Runtime (Sum of Avg Query Times, 98 Passed Queries)"
  data={{
    labels: ['Shared-Nothing (EBS)', 'Shared-Data (S3+NVMe)'],
    datasets: [
      {
        label: 'Total Runtime (seconds)',
        data: [178.6, 193.8],
        backgroundColor: ['#27ae60', '#e67e22'],
        borderColor: ['#229954', '#d35400'],
        borderWidth: 1,
      },
    ],
  }}
  options={{
    scales: {
      y: {
        title: { display: true, text: 'Total time (seconds)' },
      },
    },
  }}
/>

<BarChart
  title="Mean Query Time (ms)"
  data={{
    labels: ['Shared-Nothing (EBS)', 'Shared-Data (S3+NVMe)'],
    datasets: [
      {
        label: 'Mean Avg Time (ms)',
        data: [1822, 1977],
        backgroundColor: ['#27ae60', '#e67e22'],
        borderColor: ['#229954', '#d35400'],
        borderWidth: 1,
      },
    ],
  }}
  options={{
    scales: {
      y: {
        title: { display: true, text: 'Milliseconds' },
      },
    },
  }}
/>

**Shared-nothing is 7.8% faster overall** (178.6s vs 193.8s). The gap is smaller than expected — S3 + NVMe cache is very competitive once warm.

### Per-Cluster Headlines

<div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '1rem', marginBottom: '2rem' }}>

<div style={{ background: '#f8f9fa', padding: '1.25rem', borderRadius: '8px', border: '1px solid #e67e22' }}>

#### Shared-Nothing Results

<div style={{ display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: '0.5rem', marginBottom: '1rem' }}>
  <div style={{ background: '#fff', padding: '0.75rem', borderRadius: '6px', textAlign: 'center' }}>
    <div style={{ fontSize: '1.5rem', fontWeight: 'bold', color: '#27ae60' }}>98/99</div>
    <div style={{ color: '#666', fontSize: '0.85rem' }}>Queries Passed</div>
  </div>
  <div style={{ background: '#fff', padding: '0.75rem', borderRadius: '6px', textAlign: 'center' }}>
    <div style={{ fontSize: '1.5rem', fontWeight: 'bold', color: '#2196f3' }}>1,822ms</div>
    <div style={{ color: '#666', fontSize: '0.85rem' }}>Mean Query Time</div>
  </div>
  <div style={{ background: '#fff', padding: '0.75rem', borderRadius: '6px', textAlign: 'center' }}>
    <div style={{ fontSize: '1.5rem', fontWeight: 'bold', color: '#9b59b6' }}>178.6s</div>
    <div style={{ color: '#666', fontSize: '0.85rem' }}>Total Runtime</div>
  </div>
  <div style={{ background: '#fff', padding: '0.75rem', borderRadius: '6px', textAlign: 'center' }}>
    <div style={{ fontSize: '1.5rem', fontWeight: 'bold', color: '#e74c3c' }}>1</div>
    <div style={{ color: '#666', fontSize: '0.85rem' }}>Timeout</div>
  </div>
</div>

</div>

<div style={{ background: '#f8f9fa', padding: '1.25rem', borderRadius: '8px', border: '1px solid #3498db' }}>

#### Shared-Data Results

<div style={{ display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: '0.5rem', marginBottom: '1rem' }}>
  <div style={{ background: '#fff', padding: '0.75rem', borderRadius: '6px', textAlign: 'center' }}>
    <div style={{ fontSize: '1.5rem', fontWeight: 'bold', color: '#27ae60' }}>98/99</div>
    <div style={{ color: '#666', fontSize: '0.85rem' }}>Queries Passed</div>
  </div>
  <div style={{ background: '#fff', padding: '0.75rem', borderRadius: '6px', textAlign: 'center' }}>
    <div style={{ fontSize: '1.5rem', fontWeight: 'bold', color: '#2196f3' }}>1,977ms</div>
    <div style={{ color: '#666', fontSize: '0.85rem' }}>Mean Query Time</div>
  </div>
  <div style={{ background: '#fff', padding: '0.75rem', borderRadius: '6px', textAlign: 'center' }}>
    <div style={{ fontSize: '1.5rem', fontWeight: 'bold', color: '#9b59b6' }}>193.8s</div>
    <div style={{ color: '#666', fontSize: '0.85rem' }}>Total Runtime</div>
  </div>
  <div style={{ background: '#fff', padding: '0.75rem', borderRadius: '6px', textAlign: 'center' }}>
    <div style={{ fontSize: '1.5rem', fontWeight: 'bold', color: '#e74c3c' }}>1</div>
    <div style={{ color: '#666', fontSize: '0.85rem' }}>Timeout</div>
  </div>
</div>

</div>

</div>

### Latency Distribution

Both architectures produce similar query latency distributions. Most queries complete in under 2 seconds regardless of storage backend:

<div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '1rem' }}>

<PieChart
  title="Shared-Nothing: Query Latency Distribution"
  type="doughnut"
  data={{
    labels: [
      '< 500ms',
      '500ms - 2s',
      '2s - 5s',
      '5s - 10s',
      '10s+',
      'Timeout',
    ],
    datasets: [
      {
        label: 'Queries',
        data: [30, 35, 20, 8, 5, 1],
        backgroundColor: [
          '#27ae60',
          '#2ecc71',
          '#f39c12',
          '#e67e22',
          '#e74c3c',
          '#c0392b',
        ],
        borderColor: '#ffffff',
        borderWidth: 2,
      },
    ],
  }}
/>

<PieChart
  title="Shared-Data: Query Latency Distribution"
  type="doughnut"
  data={{
    labels: [
      '< 500ms',
      '500ms - 2s',
      '2s - 5s',
      '5s - 10s',
      '10s+',
      'Timeout',
    ],
    datasets: [
      {
        label: 'Queries',
        data: [23, 37, 20, 10, 8, 1],
        backgroundColor: [
          '#27ae60',
          '#2ecc71',
          '#f39c12',
          '#e67e22',
          '#e74c3c',
          '#c0392b',
        ],
        borderColor: '#ffffff',
        borderWidth: 2,
      },
    ],
  }}
/>

</div>

### Slowest Queries (Shared-Data)

The top-10 slowest queries in the shared-data cluster, based on avg time across 3 iterations:

| Rank | Query | Avg (ms) | Min (ms) | Max (ms) | Notes |
|------|-------|----------|----------|----------|-------|
| 1 | **q23** | 35,902 | 34,311 | 38,155 | 3-way cross-join across fact tables |
| 2 | q04 | 7,878 | 4,880 | 12,859 | Heavy `customer` window functions |
| 3 | q14 | 6,938 | 5,639 | 9,454 | 3-way self-join on `item` |
| 4 | q03 | 6,511 | 740 | 18,041 | Wide variance — cache warmup effect |
| 5 | q67 | 6,412 | 6,392 | 6,432 | Deep window functions over store_sales |
| 6 | q78 | 6,171 | 5,991 | 6,506 | Multi-aggregation on web_sales |
| 7 | q09 | 5,931 | 3,386 | 10,943 | Case-when aggregations |
| 8 | q28 | 5,224 | 2,603 | 10,465 | Multi-union aggregations |
| 9 | q59 | 5,155 | 3,175 | 6,146 | Week-over-week analysis |
| 10 | q75 | 5,127 | 4,396 | 6,533 | Multi-year comparison |
| — | **q95** | timeout | — | — | Complex web_sales self-join (same timeout on both clusters) |

### Where Shared-Nothing Wins

Most queries are 5-15% faster on shared-nothing due to lower EBS latency. The biggest wins are on queries with many small scans:

| Query | Shared-Nothing (avg ms) | Shared-Data (avg ms) | Speedup |
|-------|-------------------------|----------------------|---------|
| q13 | ~2,800 | 3,884 | 28% faster |
| q28 | ~3,100 | 5,224 | 41% faster |
| q88 | ~2,400 | 3,932 | 39% faster |

### Where Shared-Data Matches or Wins

A handful of queries perform similarly or slightly better on shared-data, particularly small aggregations where the NVMe cache acts as a dedicated fast-path:

| Query | Shared-Nothing (avg ms) | Shared-Data (avg ms) | Difference |
|-------|-------------------------|----------------------|------------|
| q93 | 237 | 237 | ~Equal |
| q99 | 93 | 93 | ~Equal |
| q41 | 92 | 92 | ~Equal |

## Resource Utilization

Observed during benchmark execution via `kubectl top pods` and Grafana:

### CPU Utilization

| | Shared-Data CN | Shared-Nothing BE |
|---|----------------|---------------------|
| **Peak CPU during query** | ~3,000m (~9.4% of 32 vCPU) | ~4,000m (~12.5%) |
| **Avg CPU during benchmark** | ~2,200m (~7%) | ~3,000m (~9%) |
| **Idle CPU** | &lt;100m | &lt;50m |

**Observation**: Neither architecture is CPU-bound at 1TB scale. The bottleneck is I/O (S3+NVMe vs EBS) and query planning on the FE. At 10TB scale, CPU saturation would become more relevant — consider that for capacity planning.

### Memory Footprint

| | Shared-Data CN | Shared-Nothing BE |
|---|----------------|---------------------|
| **Baseline memory** | ~94 GiB (37% of 256) | ~85 GiB (33% of 256) |
| **Peak memory during query** | ~105 GiB (41%) | ~95 GiB (37%) |
| **Contents** | Data cache + query buffers + tablet metadata | Page cache + tablet metadata (always resident) |

**Observation**: Both architectures carry a significant baseline memory footprint. The BE doesn't consume less memory just because it's idle — StarRocks pre-loads tablet metadata and keeps page cache hot. Budget for ~85-95 GiB baseline per node regardless of query load.

### Storage I/O

- **Shared-Nothing**: EBS IOPS approached the 6,000 provisioned limit on iteration 1 (cold read) but stayed well below on warm iterations thanks to Linux page cache
- **Shared-Data**: Iteration 1 generates ~600 MB/s of S3 GET traffic per CN (network-bound on cold cache). Iterations 2-3 drop S3 traffic to near-zero as NVMe cache serves reads

## Cost Analysis (Monthly, us-east-1)

| Component | Shared-Data | Shared-Nothing |
|-----------|-------------|----------------|
| **3× FE (m6g.2xlarge)** | $560 | $560 |
| **3× CN/BE (r8gd/r8g.8xlarge)** | ~$4,220 | ~$3,580 |
| **Data storage (1TB compressed)** | S3: ~$30 (1TB @ $0.023/GB) | EBS: ~$120 (1.5TB @ $0.08/GB) |
| **EBS for FE + logs** | ~$30 | ~$30 |
| **Total (3-node cluster)** | **~$4,840/month** | **~$4,290/month** |

:::note
r8gd costs ~18% more than r8g due to included NVMe SSD. This covers the storage offload from S3 → local cache.
:::

At **1 TB scale**, shared-nothing is cheaper by ~$550/month (~13%). As data grows:

| Dataset Size | Shared-Data Storage | Shared-Nothing Storage | Storage Delta |
|--------------|---------------------|------------------------|---------------|
| 1 TB | $23/mo | $80/mo | +$57/mo |
| 10 TB | $230/mo | $800/mo (scaling BE) | +$570/mo |
| 100 TB | $2,300/mo | $8,000/mo | +$5,700/mo |
| 1 PB | $23,000/mo | $80,000/mo | +$57,000/mo |

The inflection point for shared-data cost advantage is around **5-8 TB of stored data** (after compression).

### Factor In: Scale-to-Zero (Shared-Data Only)

With KEDA autoscaling (scale CN to 0 during idle), shared-data can save an additional **~$1,400/month per CN** during nights/weekends. For a 3-CN cluster idle 60% of the time, that's an extra **~$2,500/month savings**.

## When To Use Which

<div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '1rem', marginBottom: '1.5rem' }}>

<div style={{ background: '#e3f2fd', padding: '1.25rem', borderRadius: '8px', borderLeft: '4px solid #2196f3' }}>

### Choose Shared-Data When

- **Unpredictable workloads** — queries arrive in bursts, need scale-out
- **Large datasets** (&gt;10 TB after compression)
- **Multi-tenant** — different users want different compute sizes
- **Cost-sensitive storage** — pay-as-you-grow with S3
- **Cloud-native ops** — want to treat compute as cattle
- **Need multi-AZ DR** — S3 provides it for free
- **Scale-to-zero needs** — idle weekends/nights are free

**Examples**: Data lakehouse queries, ad-hoc analytics, multi-team data platforms

</div>

<div style={{ background: '#fff3e0', padding: '1.25rem', borderRadius: '8px', borderLeft: '4px solid #e67e22' }}>

### Choose Shared-Nothing When

- **Predictable workloads** — steady traffic, known query patterns
- **Consistent low latency required** — dashboards, real-time analytics
- **Smaller datasets** (&lt; 10 TB)
- **Dedicated cluster** — single team, stable compute
- **Simpler operations** — familiar DBA patterns
- **No S3 latency budget** — every query must be sub-second
- **Every millisecond counts** — 7.8% faster at 1TB scale

**Examples**: BI dashboards, customer-facing analytics, real-time reporting

</div>

</div>

## Reproducing This Benchmark

Full step-by-step guide: **[TPC-DS Benchmark on StarRocks](/docs/datastacks/databases/starrocks-on-eks/tpcds-benchmark)**

Infrastructure setup: **[StarRocks Infrastructure Deployment](/docs/datastacks/databases/starrocks-on-eks/infra)**

Code: [data-stacks/starrocks-on-eks](https://github.com/awslabs/data-on-eks/tree/main/data-stacks/starrocks-on-eks)

## References

- [StarRocks Shared-Data Deployment](https://docs.starrocks.io/docs/deployment/shared_data/shared_data_aws/)
- [StarRocks Cluster Planning](https://docs.starrocks.io/docs/deployment/plan_cluster/)
- [StarRocks Data Cache](https://docs.starrocks.io/docs/data_source/data_cache/)
- [TPC-DS Specification](https://www.tpc.org/tpcds/)
