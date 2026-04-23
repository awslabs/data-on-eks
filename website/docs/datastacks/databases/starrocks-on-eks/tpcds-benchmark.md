---
title: TPC-DS Benchmark
sidebar_label: TPC-DS Benchmark
sidebar_position: 1
---

# TPC-DS Benchmark on StarRocks

Run the industry-standard TPC-DS decision support benchmark on your StarRocks clusters to compare **shared-data** (S3 + CN) vs **shared-nothing** (EBS + BE) architectures on EKS.

## Overview

[TPC-DS](https://www.tpc.org/tpcds/) models a decision support system with complex queries covering reporting, ad-hoc, iterative OLAP, and data mining workloads. This guide walks through:

1. Generating 1TB of TPC-DS data
2. Loading data into both cluster types
3. Running all 99 benchmark queries (3 iterations each)
4. Monitoring with Grafana
5. Comparing results

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    EBS Volume (PVC: tpcds-data-pvc)             │
│                    1Ti gp3 — raw .dat files (~911GB)            │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                    stream_load API
                    (HTTP PUT to FE)
                           │
              ┌────────────┴────────────┐
              ▼                         ▼
┌──────────────────────┐  ┌──────────────────────────┐
│  Shared-Data Cluster │  │  Shared-Nothing Cluster  │
│  FE → S3 storage     │  │  FE → BE (EBS volumes)   │
│  CN queries S3       │  │  BE stores + computes    │
│  NVMe SSD for cache  │  │  gp3-starrocks 6000 IOPS │
└──────────────────────┘  └──────────────────────────┘
```

## Prerequisites

- StarRocks stack deployed following the [Infrastructure Guide](./infra)
- Both clusters running:

```bash
kubectl get starrockscluster -n starrocks
```

Expected:
```
NAME                       PHASE     FESTATUS   BESTATUS   CNSTATUS
starrocks-shared-data      running   running               running
starrocks-shared-nothing   running   running    running
```

## Cluster Specifications

Both clusters use identical compute resources. The only difference is the storage architecture.

### Shared-Data Cluster

| Component | Replicas | Instance Type | vCPU | Memory | Storage |
|-----------|----------|---------------|------|--------|---------|
| **FE** | 3 | m6g.2xlarge | 8 | 32 GiB | 100Gi gp3 (metadata) + 10Gi gp3 (logs) |
| **CN** | 3 | r8gd.8xlarge | 32 | 256 GiB | 1×1.9TB NVMe SSD (RAID0, data cache) |

- **Pod resources**: 28 CPU / 220Gi request, 31 CPU / 240Gi limit
- **Storage**: S3 (primary) + NVMe SSD cache (1.9TB per CN)
- **Cache**: Karpenter `instanceStorePolicy: RAID0`, mounted at `/mnt/k8s-disks`

### Shared-Nothing Cluster

| Component | Replicas | Instance Type | vCPU | Memory | Storage |
|-----------|----------|---------------|------|--------|---------|
| **FE** | 3 | m6g.2xlarge | 8 | 32 GiB | 100Gi gp3 (metadata) + 10Gi gp3 (logs) |
| **BE** | 3 | r8g.8xlarge | 32 | 256 GiB | 500Gi gp3-starrocks EBS (6000 IOPS, 250 MB/s) |

- **Pod resources**: 28 CPU / 220Gi request, 31 CPU / 240Gi limit
- **Storage**: EBS PVCs using `gp3-starrocks` StorageClass (encrypted, xfs)

### Why These Instance Types?

StarRocks recommends a **1:4+ vCPU:GB memory ratio** for compute nodes. Memory-optimized instances (r8gd/r8g) provide a 1:8 ratio, which is ideal for:
- Vectorized hash joins and aggregation state
- Data cache page cache (CN)
- Bloom filters, dictionary caches, metadata caches

The `d` suffix (r8gd) provides local NVMe SSD for the shared-data CN cache. The shared-nothing BE uses EBS PVCs instead since data persistence is required.

## Step 1: Generate TPC-DS Data

The data generation job creates raw `.dat` files on an EBS-backed PVC. This is a one-time step — the generated data is reused for loading into both clusters.

```bash
./examples/deploy-tpcds-datagen.sh
```

This creates:
- A **1Ti PVC** (`tpcds-data-pvc`) for storing generated data
- A **generator job** using 32 parallel `dsdgen` workers

Monitor progress:

```bash
# Watch logs
kubectl logs -f job/tpcds-datagen-1tb -n starrocks

# Check disk usage (while running)
kubectl exec $(kubectl get pod -l job-name=tpcds-datagen-1tb -n starrocks -o name) \
  -n starrocks -- du -sh /data/tpcds-1tb/

# Check CPU utilization
kubectl top pod -l job-name=tpcds-datagen-1tb -n starrocks
```

Verify completion:

```bash
# Job should show STATUS=Complete
kubectl get job tpcds-datagen-1tb -n starrocks
```

:::info Generation Time
With 32 parallel workers on a memory-optimized Graviton instance, data generation takes approximately **2 hours**. The output is ~911GB of pipe-delimited `.dat` files across ~10,015 files.
:::

## Step 2: Load Data into Clusters

The data loader creates TPC-DS tables and uses StarRocks `_stream_load` API to push `.dat` files from the PVC into a target cluster.

### Load into Shared-Data Cluster

```bash
./examples/deploy-tpcds-loader.sh shared-data
```

Data flows: **PVC → stream_load → FE → S3** (StarRocks handles S3 writes automatically via `run_mode = shared_data`)

### Load into Shared-Nothing Cluster

```bash
./examples/deploy-tpcds-loader.sh shared-nothing
```

Data flows: **PVC → stream_load → FE → BE (EBS volumes)**

Monitor loading:

```bash
kubectl logs -f job/tpcds-data-loader -n starrocks
```

Verify row counts after loading:

```bash
# Port-forward to the target cluster
kubectl port-forward svc/starrocks-shared-data-fe-service 9030:9030 -n starrocks

# Check counts
mysql -h 127.0.0.1 -P 9030 -u root -e "
  USE tpcds;
  SELECT 'store_sales' as tbl, count(*) as rows FROM store_sales
  UNION ALL SELECT 'catalog_sales', count(*) FROM catalog_sales
  UNION ALL SELECT 'web_sales', count(*) FROM web_sales;
"
```

Expected output:
```
tbl             rows
store_sales     2750394987
catalog_sales   1503483342
web_sales       719730368
```

:::info Loading Time
Loading ~911GB of data takes approximately **5-7 hours** per cluster. The loader is single-threaded (one file at a time via curl). Run both loaders sequentially since they share the same PVC (`ReadWriteOnce`).
:::

## Step 3: Run TPC-DS Benchmark

The benchmark runs all 99 TPC-DS queries with 3 iterations, reporting min/avg/max per query.

### Benchmark Shared-Data Cluster

```bash
kubectl delete job tpcds-benchmark -n starrocks --ignore-not-found
kubectl apply -f examples/tpcds-benchmark.yaml
```

### Benchmark Shared-Nothing Cluster

```bash
kubectl delete job tpcds-benchmark -n starrocks --ignore-not-found
sed 's|starrocks-shared-data-fe-service|starrocks-shared-nothing-fe-service|g' \
  examples/tpcds-benchmark.yaml | kubectl apply -f -
```

Monitor:

```bash
kubectl logs -f job/tpcds-benchmark -n starrocks
```

The benchmark produces a summary with per-query min/avg/max across 3 iterations:

```
Per-Query Results (min/avg/max across 3 iterations):
--------------------------------------------------------------
Query         Min(ms)  Avg(ms)  Max(ms)   Status
--------------------------------------------------------------
query01          1234     1456     1599       OK
query02          5890     6100     6328       OK
...
--------------------------------------------------------------

Overall:
  Queries passed:  98 / 99
  Queries failed:  1 / 99
  Sum of avg times: 204549ms (204s)
  Mean avg time:   2087ms
```

:::info Benchmark Duration
Each iteration takes ~15-20 minutes (99 queries). With 3 iterations, the full benchmark takes approximately **45-60 minutes** per cluster.
:::

## Step 4: Monitor with Grafana

StarRocks metrics are automatically scraped by Prometheus via PodMonitors deployed as part of the stack.

### Access Grafana

```bash
# Port-forward Grafana
kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring

# Get credentials
kubectl get secret grafana-admin-secret -n monitoring \
  -o jsonpath='{.data.admin-password}' | base64 -d
```

Open http://localhost:3000 and import the StarRocks dashboard from `infra/terraform/grafana-dashboards/starrocks-dashboard.json`.

### Cluster Filtering

The dashboard supports filtering by cluster name via the `cluster_name` dropdown. Each StarRocksCluster CR name becomes a selectable filter:
- `starrocks-shared-data`
- `starrocks-shared-nothing`

This works automatically for any new cluster — the PodMonitors extract the cluster name from the operator label `app.starrocks.ownerreference/name`.

### Key Metrics to Watch During Benchmark

| Metric | What to Look For |
|--------|-----------------|
| **Cluster QPS** | Query throughput during benchmark |
| **99th Latency** | Tail latency per FE instance |
| **BE CPU Idle** | CPU saturation on BE nodes (shared-nothing) |
| **BE Mem** | Memory pressure on BE nodes |
| **BE Compaction Score** | Should stay below 100 during queries |
| **Disk IO Util** | EBS I/O saturation (shared-nothing) |

### NVMe Cache Verification (Shared-Data)

Verify the NVMe cache is working on CN nodes:

```bash
# Check cache size on each CN
for cn in starrocks-shared-data-cn-0 starrocks-shared-data-cn-1 starrocks-shared-data-cn-2; do
  echo -n "$cn: "
  kubectl exec $cn -n starrocks -- du -sh /mnt/k8s-disks/datacache/ 2>/dev/null
done
```

Run a query twice to measure cache effect:

```bash
# Cold query (reads from S3)
time kubectl exec starrocks-shared-data-fe-0 -n starrocks -- \
  mysql -h127.0.0.1 -P9030 -uroot -e \
  "USE tpcds; SELECT count(*), avg(ss_quantity) FROM store_sales WHERE ss_sold_date_sk BETWEEN 2451911 AND 2451941;"

# Warm query (reads from NVMe cache — should be ~10x faster)
time kubectl exec starrocks-shared-data-fe-0 -n starrocks -- \
  mysql -h127.0.0.1 -P9030 -uroot -e \
  "USE tpcds; SELECT count(*), avg(ss_quantity) FROM store_sales WHERE ss_sold_date_sk BETWEEN 2451911 AND 2451941;"
```

## Connecting via SQL Client

You can connect to either cluster using any MySQL-compatible client.

### Port-Forward

```bash
# Shared-Data (port 9030)
kubectl port-forward svc/starrocks-shared-data-fe-service 9030:9030 -n starrocks

# Shared-Nothing (port 9031 — different local port)
kubectl port-forward svc/starrocks-shared-nothing-fe-service 9031:9030 -n starrocks
```

### Connect

```bash
# CLI
mysql -h 127.0.0.1 -P 9030 -u root   # shared-data
mysql -h 127.0.0.1 -P 9031 -u root   # shared-nothing
```

**Mac GUI tools**: DBeaver (`brew install --cask dbeaver-community`), TablePlus, or Sequel Ace — connect as MySQL with host `127.0.0.1`, port `9030`/`9031`, user `root`, no password.

## File Reference

| File | Purpose |
|------|---------|
| `examples/tpcds-datagen-1tb.yaml` | Job: generates 1TB TPC-DS raw data (32 parallel workers) |
| `examples/deploy-tpcds-datagen.sh` | Script: deploys data generation job |
| `examples/tpcds-data-loader.yaml` | Job: loads data from PVC into a StarRocks cluster |
| `examples/deploy-tpcds-loader.sh` | Script: deploys data loader for a target cluster |
| `examples/tpcds_create.sql` | SQL: TPC-DS table DDL (24 tables) |
| `examples/tpcds-benchmark.yaml` | Job: runs 99 TPC-DS queries (3 iterations, min/avg/max) |
| `examples/starrocks-shared-data.yaml` | StarRocksCluster: shared-data mode (FE + CN + S3) |
| `examples/starrocks-shared-nothing.yaml` | StarRocksCluster: shared-nothing mode (FE + BE + EBS) |
| `examples/deploy-shared-data.sh` | Script: deploys shared-data cluster (substitutes S3 vars) |
| `examples/deploy-shared-nothing.sh` | Script: deploys shared-nothing cluster |

## Cleanup

```bash
# Delete benchmark and loader jobs
kubectl delete job tpcds-benchmark tpcds-data-loader -n starrocks --ignore-not-found

# Delete clusters
kubectl delete starrockscluster starrocks-shared-data starrocks-shared-nothing -n starrocks

# Delete generated data PVC
kubectl delete pvc tpcds-data-pvc -n starrocks

# Destroy all infrastructure
cd data-stacks/starrocks-on-eks && ./cleanup.sh
```

:::warning
`cleanup.sh` destroys all resources including the EKS cluster, S3 buckets, and VPC. Ensure you've backed up any important data before running it.
:::
