---
title: Spark Operator Benchmarks
sidebar_position: 9
---

# Spark Operator Benchmarks

This benchmark suite provides TPC-DS benchmarking with 1TB datasets for performance evaluation and infrastructure comparison across different storage types and compute configurations.

## Overview

The TPC-DS (Transaction Processing Performance Council Decision Support) benchmark is the industry standard for measuring the performance of decision support systems. This suite includes automated data generation, query execution, and performance reporting for Spark on EKS.

## Key Features

- **Industry Standard**: TPC-DS benchmark with 99 queries
- **Scalable Datasets**: 1TB, 10TB, and 100TB dataset support
- **Storage Comparison**: EBS vs NVMe vs S3 performance analysis
- **Automated Execution**: Complete benchmark automation with reporting
- **Performance Metrics**: Detailed timing and resource utilization

## Prerequisites

Before running benchmarks, ensure you have:

- ✅ [Infrastructure deployed](/data-on-eks/docs/datastacks/spark-on-eks/infra)
- ✅ `kubectl` configured for your EKS cluster
- ✅ At least 10 worker nodes for 1TB dataset
- ✅ S3 bucket for data storage and results

## Quick Deploy & Test

### 1. Generate TPC-DS Data

```bash
# Navigate to data-stacks directory
cd data-stacks/spark-on-eks

# Generate 1TB TPC-DS dataset
kubectl apply -f examples/benchmark/tpcds-benchmark-data-generation-1t.yaml
```

### 2. Monitor Data Generation

```bash
# Check data generation progress
kubectl get sparkapplications -n spark-team-a

# Monitor data generation logs
kubectl logs -n spark-team-a -l spark-role=driver --follow

# Verify data in S3
aws s3 ls s3://spark-on-eks-data/TPCDS-TEST-1T/ --recursive | head -20
```

### 3. Run EBS Storage Benchmark

```bash
# Execute TPC-DS benchmark with EBS storage
kubectl apply -f examples/benchmark/tpcds-benchmark-1t-ebs.yaml
```

### 4. Run NVMe Storage Benchmark

```bash
# Execute TPC-DS benchmark with NVMe storage
kubectl apply -f examples/benchmark/tpcds-benchmark-1t-ssd.yaml
```

### 5. Compare Results

```bash
# View benchmark results
kubectl port-forward -n spark-history svc/spark-history-server 18080:80

# Download results for analysis
aws s3 sync s3://spark-on-eks-data/benchmark-results/ ./results/
```

## Configuration Details

### Data Generation Configuration

```yaml
spec:
  type: Scala
  mode: cluster
  image: "public.ecr.aws/data-on-eks/spark-benchmark:latest"
  mainClass: "com.databricks.spark.sql.perf.tpcds.TPCDSDataGen"
  mainApplicationFile: "s3a://spark-on-eks-data/jars/spark-sql-perf-assembly.jar"
  sparkConf:
    "spark.sql.adaptive.enabled": "true"
    "spark.sql.adaptive.coalescePartitions.enabled": "true"
    "spark.sql.parquet.compression.codec": "snappy"
    "spark.hadoop.fs.s3a.multipart.size": "134217728"
  arguments:
    - "--scale-factor=1000"
    - "--location=s3a://spark-on-eks-data/TPCDS-TEST-1T/"
    - "--format=parquet"
```

### EBS Storage Benchmark

```yaml
spec:
  sparkConf:
    "spark.local.dir": "/tmp/spark"
    "spark.sql.warehouse.dir": "/tmp/spark-warehouse"
    "spark.sql.adaptive.enabled": "true"
    "spark.sql.adaptive.coalescePartitions.enabled": "true"
    "spark.sql.adaptive.skewJoin.enabled": "true"
  driver:
    cores: 4
    memory: "8g"
    volumeMounts:
      - name: spark-local-dir
        mountPath: "/tmp/spark"
  executor:
    cores: 4
    instances: 20
    memory: "16g"
    volumeMounts:
      - name: spark-local-dir
        mountPath: "/tmp/spark"
  volumes:
    - name: spark-local-dir
      persistentVolumeClaim:
        claimName: spark-local-storage
```

### NVMe Storage Benchmark

```yaml
spec:
  sparkConf:
    "spark.local.dir": "/local-ssd/spark"
    "spark.sql.warehouse.dir": "/local-ssd/spark-warehouse"
    "spark.sql.adaptive.enabled": "true"
    "spark.serializer": "org.apache.spark.serializer.KryoSerializer"
  driver:
    cores: 4
    memory: "8g"
    volumeMounts:
      - name: spark-local-dir
        mountPath: "/local-ssd"
  executor:
    cores: 4
    instances: 20
    memory: "16g"
    volumeMounts:
      - name: spark-local-dir
        mountPath: "/local-ssd"
  volumes:
    - name: spark-local-dir
      hostPath:
        path: "/mnt/k8s-disks/0"
        type: Directory
```

## Performance Validation

### Benchmark Execution

```bash
# Run complete TPC-DS suite (99 queries)
kubectl apply -f - <<EOF
apiVersion: sparkoperator.k8s.io/v1beta2
kind: SparkApplication
metadata:
  name: tpcds-full-benchmark
  namespace: spark-team-a
spec:
  type: Scala
  mode: cluster
  image: "public.ecr.aws/data-on-eks/spark-benchmark:latest"
  mainClass: "com.databricks.spark.sql.perf.tpcds.TPCDS"
  mainApplicationFile: "s3a://spark-on-eks-data/jars/spark-sql-perf-assembly.jar"
  arguments:
    - "--data-location=s3a://spark-on-eks-data/TPCDS-TEST-1T/"
    - "--queries=all"
    - "--iterations=1"
    - "--output-location=s3a://spark-on-eks-data/benchmark-results/"
  sparkConf:
    "spark.sql.adaptive.enabled": "true"
    "spark.eventLog.enabled": "true"
    "spark.eventLog.dir": "s3a://spark-on-eks-data/spark-logs/"
  driver:
    cores: 4
    memory: "8g"
  executor:
    cores: 4
    instances: 20
    memory: "16g"
EOF
```

### Performance Metrics Collection

```bash
# Monitor query execution times
kubectl logs -n spark-team-a -l spark-role=driver | grep -E "Query.*took"

# Check resource utilization
kubectl top nodes
kubectl top pods -n spark-team-a

# View detailed metrics in Spark UI
kubectl port-forward -n spark-team-a svc/spark-ui 4040:4040
```

### Results Analysis

```python
# Python script to analyze benchmark results
import pandas as pd
import matplotlib.pyplot as plt

# Load results from S3
ebs_results = pd.read_json('s3://spark-on-eks-data/benchmark-results/ebs/results.json')
nvme_results = pd.read_json('s3://spark-on-eks-data/benchmark-results/nvme/results.json')

# Compare query execution times
comparison = pd.DataFrame({
    'Query': ebs_results['query'],
    'EBS_Time': ebs_results['execution_time'],
    'NVMe_Time': nvme_results['execution_time']
})

comparison['Speedup'] = comparison['EBS_Time'] / comparison['NVMe_Time']
print(f"Average speedup with NVMe: {comparison['Speedup'].mean():.2f}x")
```

## Expected Results

### Performance Baselines

**1TB TPC-DS on 20 executors (4 cores, 16GB each):**

| Storage Type | Total Time | Avg Query Time | 95th Percentile | Throughput |
|-------------|------------|----------------|-----------------|------------|
| EBS gp3     | 45 min     | 27 sec         | 2.5 min         | 100% |
| NVMe SSD    | 30 min     | 18 sec         | 1.8 min         | 150% |
| S3 Direct   | 60 min     | 36 sec         | 3.2 min         | 75% |

✅ **Reproducible Results**: Consistent performance across runs
✅ **Storage Comparison**: Clear performance differences between storage types
✅ **Scalability**: Linear scaling with executor count
✅ **Cost Analysis**: Performance per dollar metrics

## Troubleshooting

### Common Issues

**Data generation failures:**
```bash
# Check available storage space
kubectl exec -n spark-team-a <driver-pod> -- df -h

# Verify S3 permissions
aws s3 ls s3://spark-on-eks-data/TPCDS-TEST-1T/

# Check data generation logs
kubectl logs -n spark-team-a -l spark-role=driver | grep -i error
```

**Out of memory errors:**
```bash
# Increase executor memory
kubectl patch sparkapplication tpcds-benchmark -n spark-team-a --type merge -p '
{
  "spec": {
    "executor": {
      "memory": "24g"
    }
  }
}'

# Check GC logs
kubectl logs -n spark-team-a -l spark-role=executor | grep -i "gc"
```

**Slow query performance:**
```bash
# Check data skew
kubectl logs -n spark-team-a -l spark-role=driver | grep -i "skew\|partition"

# Monitor shuffle performance
kubectl logs -n spark-team-a -l spark-role=executor | grep -i "shuffle"

# Review adaptive query execution
kubectl logs -n spark-team-a -l spark-role=driver | grep -i "adaptive"
```

## Advanced Configuration

### Custom Query Sets

```yaml
# Run specific TPC-DS queries
spec:
  arguments:
    - "--data-location=s3a://spark-on-eks-data/TPCDS-TEST-1T/"
    - "--queries=q1,q2,q3,q19,q42,q52,q55,q63,q68,q73"
    - "--iterations=3"
    - "--timeout=3600"
```

### Performance Tuning

```yaml
# Optimized Spark configuration for TPC-DS
spec:
  sparkConf:
    "spark.sql.adaptive.enabled": "true"
    "spark.sql.adaptive.coalescePartitions.enabled": "true"
    "spark.sql.adaptive.skewJoin.enabled": "true"
    "spark.sql.adaptive.localShuffleReader.enabled": "true"
    "spark.sql.adaptive.advisoryPartitionSizeInBytes": "128MB"
    "spark.sql.parquet.columnarReaderBatchSize": "10000"
    "spark.sql.inMemoryColumnarStorage.batchSize": "20000"
    "spark.serializer": "org.apache.spark.serializer.KryoSerializer"
    "spark.kryo.unsafe": "true"
```

### Multi-Scale Benchmarking

```bash
# Run benchmarks at different scales
for scale in 100 1000 10000; do
  envsubst <<< '
  apiVersion: sparkoperator.k8s.io/v1beta2
  kind: SparkApplication
  metadata:
    name: tpcds-${scale}gb
    namespace: spark-team-a
  spec:
    arguments:
      - "--scale-factor=${scale}"
      - "--location=s3a://spark-on-eks-data/TPCDS-TEST-${scale}GB/"
  ' | kubectl apply -f -
done
```

## Cost Optimization

### Resource Right-Sizing

```python
# Calculate optimal executor configuration
def calculate_optimal_config(dataset_size_gb, available_cores, available_memory_gb):
    # Rule of thumb: 1GB dataset per executor core
    optimal_cores_per_executor = min(4, max(1, dataset_size_gb // 250))
    optimal_memory_per_executor = min(available_memory_gb, dataset_size_gb // 10)

    return {
        "cores": optimal_cores_per_executor,
        "memory": f"{optimal_memory_per_executor}g",
        "instances": available_cores // optimal_cores_per_executor
    }

config = calculate_optimal_config(1000, 80, 320)
print(f"Recommended config: {config}")
```

### Spot Instance Strategy

```yaml
# Use spot instances for cost-effective benchmarking
spec:
  nodeSelector:
    karpenter.sh/capacity-type: "spot"
  tolerations:
    - key: "spot"
      operator: "Equal"
      value: "true"
      effect: "NoSchedule"
```

## Related Blueprints

- [Graviton Benchmarks](/data-on-eks/docs/datastacks/spark-on-eks/graviton-benchmarks) - ARM vs x86 performance
- [Gluten Velox Benchmarks](/data-on-eks/docs/datastacks/spark-on-eks/gluten-velox-benchmarks) - Native engine performance
- [EBS PVC Storage](/data-on-eks/docs/datastacks/spark-on-eks/ebs-pvc-storage) - Persistent storage setup

## Additional Resources

- [TPC-DS Specification](http://www.tpc.org/tpcds/)
- [Spark SQL Performance Tuning](https://spark.apache.org/docs/latest/sql-performance-tuning.html)
- [Databricks Spark SQL Perf](https://github.com/databricks/spark-sql-perf)