---
title: Benchmark Suite Images
sidebar_position: 13
---

# Benchmark Suite Images

Pre-built Docker images with TPC-DS toolkit, data generation utilities, and performance monitoring tools for comprehensive benchmarking.

## Overview

This blueprint provides specialized Docker images optimized for running TPC-DS and other performance benchmarks on Spark, with all necessary tools and datasets pre-configured.

## Key Features

- **TPC-DS Toolkit**: Complete benchmark suite pre-installed
- **Data Generation**: Tools for generating test datasets at scale
- **Performance Monitoring**: Built-in metrics collection
- **Multi-Scale**: Support for 1TB, 10TB, and 100TB datasets
- **Automated Reporting**: Performance report generation

## Quick Build & Deploy

### 1. Build Benchmark Image

```bash
cd data-stacks/spark-on-eks/docker

# Build benchmark suite image
docker build -t spark-benchmark:latest -f Dockerfile-benchmark .
```

### 2. Run TPC-DS Benchmark

```bash
kubectl apply -f - <<EOF
apiVersion: sparkoperator.k8s.io/v1beta2
kind: SparkApplication
metadata:
  name: tpcds-benchmark
  namespace: spark-team-a
spec:
  type: Scala
  mode: cluster
  image: "spark-benchmark:latest"
  mainClass: "com.databricks.spark.sql.perf.tpcds.TPCDS"
  driver:
    cores: 4
    memory: "8g"
  executor:
    cores: 4
    instances: 10
    memory: "16g"
EOF
```

## Expected Results

✅ **Standardized Benchmarking**: Consistent benchmark execution
✅ **Comprehensive Metrics**: Detailed performance analysis
✅ **Automated Reporting**: Generated performance reports
✅ **Scalable Testing**: Support for various dataset sizes

## Related Blueprints

- [Spark Operator Benchmarks](/data-on-eks/docs/datastacks/spark-on-eks/spark-operator-benchmarks)
- [Spark Base Images](/data-on-eks/docs/datastacks/spark-on-eks/spark-base-images)

## Additional Resources

- [TPC-DS Specification](http://www.tpc.org/tpcds/)
- [Spark SQL Performance Tuning](https://spark.apache.org/docs/latest/sql-performance-tuning.html)
