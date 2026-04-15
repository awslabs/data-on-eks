---
title: TPC-DS Benchmark
sidebar_label: TPC-DS Benchmark
sidebar_position: 1
---

# TPC-DS Benchmark on StarRocks

Run the industry-standard TPC-DS decision support benchmark on your StarRocks shared-data cluster to validate query performance at scale.

## Overview

[TPC-DS](https://www.tpc.org/tpcds/) models a decision support system with complex queries covering reporting, ad-hoc, iterative OLAP, and data mining workloads. This guide walks through generating 1TB of TPC-DS data, loading it into StarRocks, and running all 99 benchmark queries.

**What you'll do:**
1. Generate 1TB TPC-DS dataset
2. Create TPC-DS schema and tables
3. Load data via Stream Load
4. Run 99 TPC-DS queries and collect results
5. Observe CN auto-scaling under load

## Prerequisites

- StarRocks cluster deployed following the [Infrastructure Guide](./infra)
- StarRocks shared-data cluster running (`kubectl get starrocksclusters -n starrocks`)
- `kubectl` configured for your EKS cluster

Verify your cluster is ready:

```bash
kubectl get pods -n starrocks
```

Expected output:
```
NAME                                       READY   STATUS    RESTARTS   AGE
kube-starrocks-operator-xxxxxxxxx-xxxxx    1/1     Running   0          1h
starrocks-shared-data-fe-0                 1/1     Running   0          30m
starrocks-shared-data-cn-0                 1/1     Running   0          28m
```

## Step 1: Generate TPC-DS Data (1TB)

Create the PVC and data generator pod:

```bash
kubectl apply -f examples/tpcds-datagen-1tb.yaml
```

This creates:
- A **1Ti PVC** (`tpcds-data-pvc`) for storing generated data
- A **generator job** (`tpcds-datagen-1tb`) running on a memory-optimized Karpenter node with the `dsdgen` tool

Monitor progress:

```bash
kubectl logs -f job/tpcds-datagen-1tb -n starrocks
```

:::info Generation Time
Data generation for TPC-DS scale factor 1000 (SF1000) takes approximately 8-10 hours depending on instance type. The "1TB" refers to the scale factor — the actual generated `.dat` files are ~917GB of pipe-delimited text across ~10000 files. The pod exits when complete; the data persists on the PVC for loading.
:::

## Step 2: Create TPC-DS Tables

Apply the table creation ConfigMap:

```bash
kubectl apply -f examples/tpcds-tables-configmap.yaml
```

Create the database:

```bash
kubectl run mysql-client -n starrocks --rm -i --restart=Never --image=mysql:8.0 -- \
  mysql -hstarrocks-shared-data-fe-service -P9030 -uroot -e "CREATE DATABASE IF NOT EXISTS tpcds;"
```

Create all 24 TPC-DS tables:

```bash
kubectl get configmap tpcds-tables-sql -n starrocks -o jsonpath='{.data.tpcds_create\.sql}' | \
  kubectl run mysql-create -n starrocks --rm -i --restart=Never --image=mysql:8.0 -- \
  mysql -hstarrocks-shared-data-fe-service -P9030 -uroot
```

Verify tables were created:

```bash
kubectl run mysql-show -n starrocks --rm -i --restart=Never --image=mysql:8.0 -- \
  mysql -hstarrocks-shared-data-fe-service -P9030 -uroot tpcds -e "SHOW TABLES;"
```

Expected output:
```
+---------------------+
| Tables_in_tpcds     |
+---------------------+
| call_center         |
| catalog_page        |
| catalog_returns     |
| catalog_sales       |
| customer            |
| customer_address    |
| customer_demographics|
| date_dim            |
| household_demographics|
| income_band         |
| inventory           |
| item                |
| promotion           |
| reason              |
| ship_mode           |
| store               |
| store_returns       |
| store_sales         |
| time_dim            |
| warehouse           |
| web_page            |
| web_returns         |
| web_sales           |
| web_site            |
+---------------------+
```

## Step 4: Load Data via Stream Load

Run the data loader job:

```bash
kubectl apply -f examples/tpcds-data-loader.yaml
```

The job uses StarRocks [Stream Load](https://docs.starrocks.io/docs/loading/StreamLoad/) — an HTTP-based bulk loading API that sends each `.dat` file via `PUT` request to the FE endpoint. In shared-data mode, data flows through FE → CN → S3. Key settings:
- `column_separator:|` — pipe-delimited `.dat` files
- `max_filter_ratio:0.3` — tolerates up to 30% bad rows per file
- `timeout:600` — 10 minute timeout per file
- `strict_mode:false` — lenient type conversion

Monitor progress:

```bash
kubectl logs -f job/tpcds-data-loader -n starrocks
```

Example output:
```
Loading file: /data/tpcds-1tb/catalog_returns_215_1000.dat
{
    "TxnId": 8533,
    "Label": "catalog_returns_1775615706652237951",
    "Table": "catalog_returns",
    "Status": "Success",
    "Message": "OK",
    "NumberTotalRows": 143761,
    "NumberLoadedRows": 143761,
    "NumberFilteredRows": 0,
    "LoadBytes": 23308622,
    "LoadTimeMs": 1065
}
Loading file: /data/tpcds-1tb/catalog_returns_216_1000.dat
```

After loading completes, verify row counts for the largest tables:

```bash
kubectl run mysql-verify -n starrocks --rm -i --restart=Never --image=mysql:8.0 -- \
  mysql -hstarrocks-shared-data-fe-service -P9030 -uroot tpcds -e "
SELECT 'store_sales' as tbl, count(*) as cnt FROM store_sales
UNION ALL SELECT 'catalog_sales', count(*) FROM catalog_sales
UNION ALL SELECT 'web_sales', count(*) FROM web_sales
UNION ALL SELECT 'inventory', count(*) FROM inventory
UNION ALL SELECT 'customer', count(*) FROM customer;
"
```

Expected output:
```
tbl             cnt
store_sales     2750394987
catalog_sales   1429178251
web_sales       719730368
inventory       783000000
customer        12000000
```

:::info Loading Time
Loading ~537GB of data (SF1000) across ~5900 files takes approximately 1-2 hours depending on CN node count and instance type.
:::

## Step 5: Run TPC-DS Benchmark

Apply the benchmark job (includes all 99 TPC-DS queries as a ConfigMap):

```bash
kubectl apply -f examples/tpcds-benchmark.yaml
```

Monitor the benchmark:

```bash
kubectl logs -f job/tpcds-benchmark -n starrocks
```

Each query has a 600-second timeout. The job produces a summary report at the end:

```
query01: SUCCESS (6223ms)
query02: SUCCESS (12245ms)
query03: SUCCESS (12936ms)
query04: SUCCESS (20307ms)
...
query95: SUCCESS (344360ms)
query96: SUCCESS (12043ms)
query97: SUCCESS (7944ms)
query98: SUCCESS (6980ms)
query99: SUCCESS (2383ms)
Summary:
Total Queries: 99
Successful: 99
Failed: 0
Total Time: 719127ms
Average Time: 7263ms
```

:::info
All 99 TPC-DS queries completed successfully with 10 CN nodes. Average query time was ~7.3 seconds. Query 95 was the slowest at ~344 seconds due to its complex multi-way join pattern.
:::

## Step 6: Observe Auto-Scaling

While the benchmark is running, observe CN auto-scaling in a separate terminal:

```bash
# Watch HPA scaling CN replicas
kubectl get hpa -n starrocks -w
```

Expected output:
```
NAME                                  REFERENCE                                TARGETS                        MINPODS   MAXPODS   REPLICAS
starrocks-shared-data-cn-autoscaler   StarRocksCluster/starrocks-shared-data   cpu: 6%/60%, memory: 54%/60%   1         10        10
```

```bash
# Watch CN pods scaling up
kubectl get pods -n starrocks -w
```

Expected output:
```
NAME                                       READY   STATUS    AGE
starrocks-shared-data-cn-0                 1/1     Running   42h
starrocks-shared-data-cn-1                 1/1     Running   20h
starrocks-shared-data-cn-2                 1/1     Running   15h
starrocks-shared-data-cn-3                 1/1     Running   3h
starrocks-shared-data-cn-4                 1/1     Running   17m
starrocks-shared-data-cn-5                 1/1     Running   17m
starrocks-shared-data-cn-6                 0/1     Pending   16m
starrocks-shared-data-cn-7                 0/1     Pending   16m
starrocks-shared-data-cn-8                 0/1     Pending   14m
starrocks-shared-data-cn-9                 0/1     Pending   14m
```

The CN HPA scales from 1 to 10 replicas based on CPU and memory utilization (target: 60%). Karpenter automatically provisions new nodes as CN pods scale up.

## Cleanup

To remove all resources:

```bash
cd data-on-eks/data-stacks/starrocks-on-eks/terraform/_local
./cleanup.sh
```

:::warning

This will delete all resources including:
- EKS cluster and all workloads
- S3 buckets (StarRocks data)
- VPC and networking resources

Ensure you've backed up any important data before cleanup.

:::
