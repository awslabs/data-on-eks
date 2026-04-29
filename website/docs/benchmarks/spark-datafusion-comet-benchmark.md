---
sidebar_position: 6
sidebar_label: Apache Spark with DataFusion Comet Benchmarks
---

import BarChart from '@site/src/components/Charts/BarChart';
import PieChart from '@site/src/components/Charts/PieChart';

## Apache Spark with Apache DataFusion Comet Benchmarks

[Apache Spark](https://spark.apache.org/) powers large-scale analytics, but its JVM-based execution faces performance limitations. [Apache DataFusion Comet](https://github.com/apache/datafusion-comet) attempts to address this by offloading compute operations to a native Rust execution engine built on [Apache Arrow DataFusion](https://arrow.apache.org/datafusion/).

This benchmark evaluates Comet's performance on [Amazon EKS](https://aws.amazon.com/eks/) using the [TPC-DS](https://www.tpc.org/tpcds/) 3TB workload.


:::info **TL;DR**
Our TPC-DS 3TB benchmark shows that **Apache DataFusion Comet (v0.15.0) delivered 11% faster overall performance** compared to native Spark SQL, with variable query-level results.
Some queries saw ~50% improvements, while others saw ~35% degradation.
:::

## TPC-DS 3TB Benchmark Results

### Summary

Our comprehensive TPC-DS 3TB benchmark on Amazon EKS demonstrates that **Apache DataFusion Comet (v0.15.0) provides an overall speedup** (**11% faster**) compared to native Spark SQL, with individual queries varying from ~50% faster to ~35% slower (one outlier at 90%, likely a measurement artifact).

| Name | Completion Time (seconds) | Speedup |
|------|---------------------------|---------|
| Native Spark | 3,650.56 | Baseline |
| Comet | 3,246.87 | **11% faster** |


### Benchmark Infrastructure

:::info Benchmark Methodology
Benchmarks ran sequentially on the same cluster to ensure identical hardware and eliminate resource contention. Native Spark executed first, followed by Comet.
:::

To ensure an apples-to-apples comparison, both native Spark and Comet jobs ran on identical hardware, storage, and data. Only the execution engine and related Spark settings differed.

#### Test Environment

| Component | Configuration |
|-----------|--------------|
| **EKS Cluster** | [Amazon EKS](https://aws.amazon.com/eks/) 1.34 |
| **Node Instance Type** | r8gd.12xlarge (48 vCPUs, 384GB RAM, 1.8TB NVMe SSD) |
| **Node Group** | 24 nodes dedicated for benchmark workloads |
| **Executor Configuration** | 23 executors × 5 cores × 58GB RAM each |
| **Driver Configuration** | 5 cores × 20GB RAM |
| **Dataset** | [TPC-DS](https://www.tpc.org/tpcds/) 3TB (Parquet format) |
| **Storage** | [Amazon S3](https://aws.amazon.com/s3/) with optimized S3A connector |

#### Spark Configuration Comparison

| Configuration | Native Spark | Comet |
|---------------|-------------|-------|
| **Spark Version** | 3.5.8 | 3.5.8 |
| **Comet Version** | N/A | 0.15.0 |
| **Java Runtime** | [OpenJDK](https://openjdk.org/) 17 | [OpenJDK](https://openjdk.org/) 17 |
| **Execution Engine** | JVM-based [Tungsten](https://spark.apache.org/docs/latest/sql-performance-tuning.html#project-tungsten) | Rust + JVM hybrid |
| **Key Plugins** | Standard Spark | `CometPlugin`, `CometShuffleManager` |
| **Off-heap Memory** | 32GB enabled | 32GB enabled |
| **Memory Management** | JVM GC | Unified native + JVM |
| **memoryThrottlingFactor** | `0.7` | `0.7` |

#### Critical Comet-Specific Configurations

```yaml
# Essential Comet Configuration
"spark.plugins": "org.apache.spark.CometPlugin"
"spark.shuffle.manager": "org.apache.spark.sql.comet.execution.shuffle.CometShuffleManager"

# Memory Configuration - Critical for Comet
"spark.memory.offHeap.enabled": "true"
"spark.memory.offHeap.size": "32g"  # Required: 16GB minimum, 32GB recommended

# Comet Execution Settings
"spark.comet.exec.enabled": "true"
"spark.comet.exec.shuffle.enabled": "true"
"spark.comet.exec.shuffle.mode": "auto"
"spark.comet.explainFallback.enabled": "true"
"spark.comet.cast.allowIncompatible": "true"
"spark.comet.dppFallback.enabled": "true"

# AWS-Specific: Required for S3 region detection
"spark.hadoop.fs.s3a.endpoint.region": "us-west-2"
```

## Performance Results

### Overall Performance

<BarChart
  title="Total Runtime Comparison"
  data={{
    labels: ['Native Spark', 'Comet'],
    datasets: [{
      label: 'Runtime (seconds)',
      data: [3650.56, 3246.87],
      backgroundColor: ['#95a5a6', '#27ae60'],
      borderColor: ['#7f8c8d', '#229954'],
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

| Name | Completion Time (seconds) | Speedup |
|------|---------------------------|---------|
| Native Spark | 3,650.56 | Baseline |
| Comet | 3,246.87 | **11% faster** |


### Performance Distribution

<PieChart
  title="Query Performance Distribution"
  type="doughnut"
  data={{
    labels: ['20%+ improvement', '10-20% improvement', '±10%', '10-20% degradation', '20%+ degradation'],
    datasets: [{
      data: [32, 19, 44, 4, 4],
      backgroundColor: ['#27ae60', '#3498db', '#f39c12', '#e67e22', '#e74c3c'],
      borderWidth: 2,
      borderColor: '#ffffff'
    }]
  }}
/>

| Performance Range | Query Count | Percentage |
|---|---|---|
| 20%+ improvement | 32 | 31% |
| 10-20% improvement | 19 | 18% |
| ±10% | 44 | 43% |
| 10-20% degradation | 4 | 4% |
| 20%+ degradation | 4 | 4% |

### Top 10 Query Improvements

<BarChart
  title="Top 10 Query Improvements (% faster with Comet)"
  data={{
    labels: ['q5-v4.0', 'q56-v4.0', 'q41-v4.0', 'q45-v4.0', 'q9-v4.0', 'q80-v4.0', 'q58-v4.0', 'q86-v4.0', 'q83-v4.0', 'q73-v4.0'],
    datasets: [
      {
        label: 'Improvement %',
        data: [51, 49, 47, 43, 42, 38, 38, 36, 36, 36],
        backgroundColor: '#27ae60',
        borderColor: '#229954',
        borderWidth: 1
      }
    ]
  }}
  options={{
    scales: {
      y: {
        beginAtZero: true,
        title: { display: true, text: 'Improvement (%)' }
      },
      x: {
        title: { display: true, text: 'TPC-DS Queries' }
      }
    }
  }}
  height="400px"
/>

| Query | Native Spark (s) | Comet (s) | Improvement |
|---|---|---|---|
| q5-v4.0 | 40.8 | 20.0 | **51%** faster |
| q56-v4.0 | 5.8 | 3.0 | **49%** faster |
| q41-v4.0 | 0.8 | 0.4 | **47%** faster |
| q45-v4.0 | 12.3 | 7.0 | **43%** faster |
| q9-v4.0 | 83.8 | 49.0 | **42%** faster |
| q80-v4.0 | 32.6 | 20.1 | **38%** faster |
| q58-v4.0 | 5.4 | 3.3 | **38%** faster |
| q86-v4.0 | 12.8 | 8.1 | **36%** faster |
| q83-v4.0 | 2.8 | 1.8 | **36%** faster |
| q73-v4.0 | 3.4 | 2.2 | **36%** faster |

### Top 10 Query Regressions

<BarChart
  title="Top 10 Query Regressions (% slower with Comet)"
  data={{
    labels: ['q32-v4.0', 'q50-v4.0', 'q39a-v4.0', 'q68-v4.0', 'q20-v4.0', 'q30-v4.0', 'q67-v4.0', 'q25-v4.0', 'q29-v4.0', 'q91-v4.0'],
    datasets: [
      {
        label: 'Degradation %',
        data: [90, 35, 23, 21, 14, 11, 11, 10, 10, 10],
        backgroundColor: '#e74c3c',
        borderColor: '#c0392b',
        borderWidth: 1
      }
    ]
  }}
  options={{
    scales: {
      y: {
        beginAtZero: true,
        title: { display: true, text: 'Degradation (%)' }
      },
      x: {
        title: { display: true, text: 'TPC-DS Queries' }
      }
    }
  }}
  height="400px"
/>

| Query | Native Spark (s) | Comet (s) | Degradation |
|---|---|---|---|
| q32-v4.0 | 2.9 | 5.6 | **90%** slower |
| q50-v4.0 | 82.7 | 111.5 | **35%** slower |
| q39a-v4.0 | 5.1 | 6.3 | **23%** slower |
| q68-v4.0 | 5.9 | 7.1 | **21%** slower |
| q20-v4.0 | 5.1 | 5.8 | **14%** slower |
| q30-v4.0 | 15.9 | 17.7 | **11%** slower |
| q67-v4.0 | 141.2 | 156.8 | **11%** slower |
| q25-v4.0 | 8.9 | 9.9 | **10%** slower |
| q29-v4.0 | 34.4 | 37.8 | **10%** slower |
| q91-v4.0 | 2.1 | 2.3 | **10%** slower |


### Notes on Performance Differences

**Why Comet Underperforms on Some Queries:**

**Example - Query 32 (-90.1%)**

- The regressing stages run identical Spark WholeStageCodegen in both apps -- no Comet operators are involved in the slow stages
- Comet's best iteration (2,132ms) is faster than Default's best (2,338ms); the median regression is driven by single-task stragglers reaching 7.1s (10.5x p50) in Comet vs 1.8s max in Default
- Measurement artifact from infrastructure-level straggler interference on a single task out of 118 in Comet's non-Comet scan stages, amplified by 6.6x wider iteration variance (range 8,856ms vs 1,351ms)

**Example - Query 39a (-23.1%)**

- Inventory scan stage median task time 35-77% higher in Comet (234ms vs 173ms) due to columnar shuffle serialization overhead
- CometColumnarExchange retained 200 partitions where Default used 7, inflating broadcast stage from 32ms to 358ms and producing 3.2x more shuffle data (23.3 MB vs 7.2 MB)
- Two compounding factors: slower scan-stage serialization to Comet's columnar format (+330-538ms), and CometColumnarExchange overriding the natural partition count with 200 partitions for a broadcast exchange that only needed 7

**Why Comet Outperforms Some Queries:**

Comet's native Rust execution engine excels at CPU-intensive operations

**Example - Query 5 (+50.9%)**

- Shuffle read on the SortMergeJoin stage dropped 92% (27.9 GB to 2.2 GB) due to Comet's native columnar shuffle for web_sales (2.16B rows)
- GC time in the scan stage dropped from 7,236ms to 77ms; CometSort was 56% faster than Spark Sort (13.9 min vs 31.9 min total)
- Comet's native scan-filter-exchange pipeline for web_sales produced compact Arrow columnar shuffle data, massively reducing downstream shuffle read and sort time in the join stage, with cascading contention reduction benefiting non-Comet stages

**Example - Query 56 (+49.0%)**

- AQE converted all three SortMergeJoins to BroadcastHashJoins because CometExchange reported customer_address shuffle size as 2.7 MiB (vs 10.7 MiB in Default), falling below the 10 MB broadcast threshold
- Combined join stage time dropped from 8.6s to 1.4s; GC dropped from 2.8s to 206ms
- Comet's Arrow columnar shuffle encoding produced a more compact representation that caused AQE to select broadcast joins, eliminating sort buffers, shuffle overhead, and GC pressure from sort buffer allocation


### Resource Usage Analysis

Both benchmarks ran sequentially on identical hardware to enable direct comparison.

#### CPU Utilization

CPU utilization showed similar patterns between Native Spark and Comet, with both sustaining comparable peak and average usage throughout the benchmark.

<div style={{display: 'flex', gap: '1rem', justifyContent: 'center', flexWrap: 'wrap'}}>
  <div style={{flex: '1 1 45%', textAlign: 'center'}}>
    <strong>Native Spark (Default)</strong>
    <img src={require('./img/comet/cpu-default.png').default} alt="CPU utilization - Native Spark" />
  </div>
  <div style={{flex: '1 1 45%', textAlign: 'center'}}>
    <strong>Comet</strong>
    <img src={require('./img/comet/cpu-comet.png').default} alt="CPU utilization - Comet" />
  </div>
</div>


#### Memory Utilization

Comet consumed more memory than Native Spark, peaking around ~52GB compared to ~48GB for Native Spark. Native Spark's memory usage returned to a baseline of ~20GB between queries, while Comet remained elevated. This is expected — Comet offloads most compute operations to its native Rust engine using off-heap memory, so the JVM heap sees less activity while native allocations persist between queries. This suggests that on-heap JVM memory per executor could potentially be reduced when running Comet, shifting the memory budget toward off-heap allocation.

<div style={{display: 'flex', gap: '1rem', justifyContent: 'center', flexWrap: 'wrap'}}>
  <div style={{flex: '1 1 45%', textAlign: 'center'}}>
    <strong>Native Spark (Default)</strong>
    <img src={require('./img/comet/memory-default.png').default} alt="Memory utilization - Native Spark" />
  </div>
  <div style={{flex: '1 1 45%', textAlign: 'center'}}>
    <strong>Comet</strong>
    <img src={require('./img/comet/memory-comet.png').default} alt="Memory utilization - Comet" />
  </div>
</div>

#### Network Bandwidth

Network bandwidth was comparable between Native Spark and Comet, with both showing similar transmit and receive throughput.

<div style={{display: 'flex', gap: '1rem', justifyContent: 'center', flexWrap: 'wrap'}}>
  <div style={{flex: '1 1 45%', textAlign: 'center'}}>
    <strong>Native Spark (Default)</strong>
    <img src={require('./img/comet/tp-default.png').default} alt="Network bandwidth - Native Spark" />
  </div>
  <div style={{flex: '1 1 45%', textAlign: 'center'}}>
    <strong>Comet</strong>
    <img src={require('./img/comet/tp-comet.png').default} alt="Network bandwidth - Comet" />
  </div>
</div>

#### Storage I/O

Storage utilization (IOPS and throughput) showed Comet with higher peak IOPS than Native Spark.

<div style={{display: 'flex', gap: '1rem', justifyContent: 'center', flexWrap: 'wrap'}}>
  <div style={{flex: '1 1 45%', textAlign: 'center'}}>
    <strong>Native Spark (Default)</strong>
    <img src={require('./img/comet/iops-default.png').default} alt="Storage IOPS - Native Spark" />
  </div>
  <div style={{flex: '1 1 45%', textAlign: 'center'}}>
    <strong>Comet</strong>
    <img src={require('./img/comet/iops-comet.png').default} alt="Storage IOPS - Comet" />
  </div>
</div>

<details>
<summary><strong>Full Grafana Dashboard — Native Spark (Default)</strong></summary>

<img src={require('./img/comet/spark-metrics-default.png').default} alt="Full Grafana dashboard - Native Spark" loading="lazy" />

</details>

<details>
<summary><strong>Full Grafana Dashboard — Comet</strong></summary>

<img src={require('./img/comet/spark-metrics-comet.png').default} alt="Full Grafana dashboard - Comet" loading="lazy" />

</details>


**Summary**: Comet uses slightly more memory than Native Spark (higher peak and elevated baseline between queries), while CPU, network, and storage utilization remain comparable. The 11% overall speedup comes without a significant increase in resource consumption. Since Comet performs most compute off-heap in its native Rust engine, operators may be able to reduce on-heap JVM memory per executor and allocate more toward off-heap, potentially improving cost efficiency.


## When to Consider Comet

Comet may be beneficial for:

- **Workloads dominated by specific query patterns** - If your workload consists primarily of queries similar to q5, q56, q41, q45 (40%+ faster), Comet could provide net benefits
- **Targeted query optimization** - Scenarios where you can isolate and route specific query patterns that align with Comet's strengths
- **Future versions** - As the project matures, performance characteristics may change and improve significantly

## Running Benchmarks

### Prerequisites

- EKS cluster with Spark Operator installed
- S3 bucket with TPC-DS benchmark data
- Docker registry access (ECR or other)

### Step 1: Build Docker Image

Build the Comet-enabled Spark image:

```bash
cd data-stacks/spark-on-eks/benchmarks/datafusion-comet-benchmarks

# Build and push to your registry
docker build -t <your-registry>/spark-comet:3.5.8 -f Dockerfile-comet .
docker push <your-registry>/spark-comet:3.5.8
```

### Step 2: Install NodeLocal DNS Cache

To mitigate the DNS query volume issue, install NodeLocal DNS Cache:

```bash
kubectl apply -f node-local-cache.yaml
```

This caches DNS results locally on each node, preventing the excessive DNS queries to Route53 Resolver.

### Step 3: Update Bucket Names

Update the S3 bucket references in the benchmark manifests:

```bash
# For Comet benchmark
export S3_BUCKET=your-bucket-name
envsubst < tpcds-benchmark-comet-parquet.yaml | kubectl apply -f -

# For native Spark baseline
envsubst < tpcds-benchmark-parquet.yaml | kubectl apply -f -
```

Or manually edit the YAML files and replace `${S3_BUCKET}` with your bucket name.

### Step 4: Monitor Benchmark Progress

```bash
# Check job status
kubectl get sparkapplications -n spark-team-a

# View logs
kubectl logs -f -n spark-team-a -l spark-app-name=tpcds-benchmark-comet
```
