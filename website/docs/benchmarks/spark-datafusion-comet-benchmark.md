---
sidebar_position: 5
sidebar_label: Apache Spark with DataFusion Comet Benchmarks
---

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';
import BarChart from '@site/src/components/Charts/BarChart';
import PieChart from '@site/src/components/Charts/PieChart';

# Apache Spark with Apache DataFusion Comet Benchmarks

[Apache Spark](https://spark.apache.org/) powers large-scale analytics, but its JVM-based execution faces performance limitations. [Apache DataFusion Comet](https://github.com/apache/datafusion-comet) attempts to address this by offloading compute operations to a native Rust execution engine built on [Apache Arrow DataFusion](https://arrow.apache.org/datafusion/).

This benchmark evaluates Comet's performance on [Amazon EKS](https://aws.amazon.com/eks/) using the [TPC-DS](https://www.tpc.org/tpcds/) 1TB workload.

:::note Version Tested
This benchmark uses Apache DataFusion Comet 0.13.0 (released January 2026). Performance characteristics may improve in future releases.
:::

:::warning Key Finding
Our TPC-DS 1TB benchmark shows that **Apache DataFusion Comet delivered 18% slower overall performance** compared to native Spark SQL, with highly variable query-level results.
:::

## TPC-DS 1TB Benchmark Results

### Summary

Our comprehensive TPC-DS 1TB benchmark on Amazon EKS demonstrates that **Apache DataFusion Comet does not provide overall speedup** (**18% slower**) compared to native Spark SQL, with individual queries showing mixed results.


#### Overall Performance

<BarChart
  title="Total Runtime Comparison"
  data={{
    labels: ['Native Spark', 'Comet'],
    datasets: [{
      label: 'Runtime (seconds)',
      data: [2090.46, 2470.43],
      backgroundColor: ['#27ae60', '#e74c3c'],
      borderColor: ['#229954', '#c0392b'],
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

#### Performance Distribution

<PieChart
  title="Query Performance Distribution"
  type="doughnut"
  data={{
    labels: ['20%+ improvement', '10-20% improvement', '±10%', '10-20% degradation', '20%+ degradation'],
    datasets: [{
      data: [25, 15, 38, 4, 22],
      backgroundColor: ['#27ae60', '#3498db', '#f39c12', '#e67e22', '#e74c3c'],
      borderWidth: 2,
      borderColor: '#ffffff'
    }]
  }}
/>


### Benchmark Infrastructure

:::info Benchmark Methodology
Benchmarks ran sequentially on the same cluster to ensure identical hardware and eliminate resource contention. Native Spark executed first, followed by Comet.
:::

To ensure an apples-to-apples comparison, both native Spark and Comet jobs ran on identical hardware, storage, and data. Only the execution engine and related Spark settings differed.

#### Test Environment

| Component | Configuration |
|-----------|--------------|
| **EKS Cluster** | [Amazon EKS](https://aws.amazon.com/eks/) 1.34 |
| **Node Instance Type** | c5d.12xlarge (48 vCPUs, 96GB RAM, 1.8TB NVMe SSD) |
| **Node Group** | 24 nodes dedicated for benchmark workloads |
| **Executor Configuration** | 23 executors × 5 cores × 58GB RAM each |
| **Driver Configuration** | 5 cores × 20GB RAM |
| **Dataset** | [TPC-DS](https://www.tpc.org/tpcds/) 1TB (Parquet format) |
| **Storage** | [Amazon S3](https://aws.amazon.com/s3/) with optimized S3A connector |

#### Spark Configuration Comparison

| Configuration | Native Spark | Comet |
|---------------|-------------|-------|
| **Spark Version** | 3.5.7 | 3.5.7 |
| **Comet Version** | N/A | 0.13.0 |
| **Java Runtime** | [OpenJDK](https://openjdk.org/) 17 | [OpenJDK](https://openjdk.org/) 17 |
| **Execution Engine** | JVM-based [Tungsten](https://spark.apache.org/docs/latest/sql-performance-tuning.html#project-tungsten) | Rust + JVM hybrid |
| **Key Plugins** | Standard Spark | `CometPlugin`, `CometShuffleManager` |
| **Off-heap Memory** | Default | 32GB enabled |
| **Memory Management** | JVM GC | Unified native + JVM |

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

# AWS-Specific: Required for S3 region detection
"spark.hadoop.fs.s3a.endpoint.region": "us-west-2"
```

### Performance Results

#### Overall Performance

| Name | Completion Time (seconds) | Performance |
|------|---------------------------|-------------|
| Native Spark | 2,090.46 | Baseline |
| Comet | 2,470.43 | **-18%** |

#### Performance Distribution

| Performance Range | Query Count | Percentage |
|-------------------|-------------|------------|
| 20%+ improvement | 25 | 24% |
| 10-20% improvement | 15 | 14% |
| ±10% (neutral) | 38 | 37% |
| 10-20% degradation | 4 | 4% |
| 20%+ degradation | 22 | 21% |

#### Top 10 Query Improvements

<BarChart
  title="Top 10 Query Improvements (% faster with Comet)"
  data={{
    labels: ['q8', 'q5', 'q41', 'q93', 'q9', 'q76', 'q90', 'q73', 'q97', 'q44'],
    datasets: [
      {
        label: 'Improvement %',
        data: [54, 47, 40, 40, 34, 34, 33, 32, 31, 30],
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
|-------|------------------|-----------|-------------|
| q8-v2.4 | 5.9 | 2.7 | **54%** faster |
| q5-v2.4 | 20.4 | 10.8 | **47%** faster |
| q41-v2.4 | 1.2 | 0.7 | **40%** faster |
| q93-v2.4 | 77.9 | 47.1 | **40%** faster |
| q9-v2.4 | 56.4 | 37.2 | **34%** faster |
| q76-v2.4 | 33.5 | 22.1 | **34%** faster |
| q90-v2.4 | 14.6 | 9.7 | **33%** faster |
| q73-v2.4 | 3.8 | 2.6 | **32%** faster |
| q97-v2.4 | 19.5 | 13.5 | **31%** faster |
| q44-v2.4 | 25.2 | 17.6 | **30%** faster |

#### Top 10 Query Regressions

<BarChart
  title="Top 10 Query Regressions (% slower with Comet)"
  data={{
    labels: ['q25', 'q17', 'q54', 'q29', 'q45', 'q6', 'q18', 'q68', 'q11', 'q74'],
    datasets: [
      {
        label: 'Degradation %',
        data: [1308, 1020, 586, 330, 316, 210, 199, 168, 162, 137],
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
|-------|------------------|-----------|-------------|
| q25-v2.4 | 5.7 | 79.9 | **1,308%** slower |
| q17-v2.4 | 6.8 | 76.5 | **1,020%** slower |
| q54-v2.4 | 6.2 | 42.3 | **586%** slower |
| q29-v2.4 | 17.7 | 76.0 | **330%** slower |
| q45-v2.4 | 6.6 | 27.6 | **316%** slower |
| q6-v2.4 | 10.2 | 31.6 | **210%** slower |
| q18-v2.4 | 10.5 | 31.3 | **199%** slower |
| q68-v2.4 | 6.6 | 17.6 | **168%** slower |
| q11-v2.4 | 25.7 | 67.4 | **162%** slower |
| q74-v2.4 | 22.1 | 52.3 | **137%** slower |

:::note
Extreme regressions (>500%) may indicate queries falling back to JVM execution while still incurring Comet's coordination overhead.
:::

### Resource Usage Analysis

Both benchmarks ran sequentially on identical hardware to enable direct comparison. Native Spark executed first, followed by Comet. The metrics below show two distinct time periods—the first representing Native Spark, the second representing Comet.

#### CPU Utilization

Comet demonstrated **significantly higher and more sustained CPU utilization** compared to Native Spark:
- **Native Spark**: 3-6 cores per executor (typical), with occasional spikes to ~6.5 cores
- **Comet**: 5-9 cores per executor (sustained), with frequent peaks reaching 9+ cores

The higher CPU utilization reflects Comet's native Rust execution engine performing more intensive computation.

![](./img/comet-cpu.png)

#### Memory Consumption

Comet required **significantly more memory** than Native Spark:
- **Native Spark**: ~24 GB per executor (observed steady state)
- **Comet**: ~40 GB per executor (observed steady state)

This represents a **67% increase in actual memory consumption** and aligns with Comet's off-heap memory requirements and dual runtime architecture (Rust + JVM).

![](./img/comet-memory.png)

#### Network Bandwidth

Network utilization patterns were comparable between Native Spark and Comet, with both showing similar bandwidth consumption for transmit and receive operations.

![](./img/comet-networking.png)

#### Storage I/O

Storage utilization (IOPS and throughput) showed similar patterns between Native Spark and Comet, indicating comparable disk I/O characteristics.

![](./img/comet-storage.png)

**Key Takeaway**: Comet's native execution engine consumes significantly more CPU and memory resources compared to Native Spark, while network and storage utilization remain comparable. Despite the increased CPU and memory consumption, the 18% overall slowdown indicates these additional resources do not translate to net performance improvements for TPC-DS workloads.


## When to Consider Comet

Despite the overall performance regression, Comet may be beneficial for:

- **Workloads dominated by specific query patterns** - If your workload consists primarily of queries similar to q8, q5, q41, q93 (30-54% faster), Comet could provide net benefits
- **Targeted query optimization** - Scenarios where you can isolate and route specific query patterns that align with Comet's strengths
- **Future versions** - As the project matures, performance characteristics may improve significantly

**Not recommended for:**

- General-purpose TPC-DS-like analytical workloads
- Memory-constrained environments (requires 2.2x memory overhead)
- Workloads requiring consistent, predictable performance across diverse query patterns

## Issues

### AWS S3 Region Detection

:::warning Required Configuration
Comet cannot reliably determine AWS region automatically. You must explicitly set the S3 endpoint region to avoid failures.
:::

**Solution:**
```yaml
"spark.hadoop.fs.s3a.endpoint.region": "us-west-2"
```

**Without this configuration, you may encounter:**

```
org.apache.comet.CometNativeException: General execution error with reason: Generic S3 error: Failed to resolve region: error sending request for url
at org.apache.comet.parquet.Native.initRecordBatchReader(Native Method)
	at org.apache.comet.parquet.NativeBatchReader.init(NativeBatchReader.java:568)
	at org.apache.comet.parquet.CometParquetFileFormat.$anonfun$buildReaderWithPartitionValues$1(CometParquetFileFormat.scala:175)

```


### Excessive DNS Query Volume

:::caution Critical Issue
Comet generates significantly higher DNS query volume compared to native Spark, potentially hitting Route53 Resolver limits.
:::

**Observed behavior:**

| Metric | Native Spark | Comet | Impact |
|--------|--------------|-------|--------|
| DNS queries/sec | 5-10 | Up to 5,000 | **500x increase** |
| Route53 limit | Well below 1,024/sec/ENI | Approaching/exceeding 1,024/sec/ENI | Limit reached |

**Symptoms:**
- `UnknownHostException` errors during job execution
- Intermittent S3 connectivity failures
- Job failures under high concurrency

**Root cause:**
Comet's native Rust layer may not leverage JVM DNS caching mechanisms, resulting in excessive DNS lookups.

**Solution:**
Deploy NodeLocal DNS Cache to cache DNS results on each node:
```bash
kubectl apply -f node-local-cache.yaml
```

Reference: [Kubernetes NodeLocal DNSCache](https://kubernetes.io/docs/tasks/administer-cluster/nodelocaldns/)

### Memory Requirements

:::caution Increased Memory Footprint
Comet requires significantly more off-heap memory compared to native Spark.
:::

**Memory comparison:**

Both benchmarks used identical pod configurations (58GB RAM per executor) to ensure fair comparison. The key differences:

| Metric | Native Spark | Comet | Difference |
|--------|--------------|-------|------------|
| Configured executor memory | 58 GB | 58 GB | Same |
| Off-heap memory configuration | Default (minimal) | 32 GB | Required for Comet |
| **Observed memory usage** | **~24 GB** | **~40 GB** | **+67%** |


**Key takeaways:**
- Native Spark only utilized ~24GB of the 58GB allocation, leaving significant headroom
- Comet required ~40GB and needs the 32GB off-heap configuration to avoid OOM
- While Native Spark can run efficiently with 26-30GB total memory, Comet requires 58GB+ to operate reliably
- This means Comet needs **2.2x more memory** than Native Spark for the same workload

## Running Benchmarks

### Prerequisites

- EKS cluster with Spark Operator installed
- S3 bucket with TPC-DS benchmark data
- Docker registry access (ECR or other)

### Step 1: Build Docker Image

Build the Comet-enabled Spark image:

```bash
cd data-stacks/spark-on-eks/benchmarks/datafusion-comet

# Build and push to your registry
docker build -t <your-registry>/spark-comet:3.5.7 -f Dockerfile-comet .
docker push <your-registry>/spark-comet:3.5.7
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
envsubst < tpcds-benchmark-comet-template.yaml | kubectl apply -f -

# For native Spark baseline
envsubst < tpcds-benchmark-357-template.yaml | kubectl apply -f -
```

Or manually edit the YAML files and replace `${S3_BUCKET}` with your bucket name.

### Step 4: Monitor Benchmark Progress

```bash
# Check job status
kubectl get sparkapplications -n spark-team-a

# View logs
kubectl logs -f -n spark-team-a -l spark-app-name=tpcds-benchmark-comet
```

