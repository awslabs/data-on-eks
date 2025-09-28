---
title: Gluten Velox Benchmarks
sidebar_position: 11
---

# Gluten Velox Benchmarks

This benchmark suite demonstrates native execution engine performance with Gluten and Velox for accelerated Spark performance and columnar processing optimization.

## Overview

Gluten is a middle layer that interfaces Spark with native libraries like Velox, providing significant performance improvements through native C++ execution engines. This benchmark suite evaluates the performance gains across different workload types.

## Key Features

- **Native Execution**: C++ native execution via Velox engine
- **Vectorized Processing**: SIMD optimizations for columnar data
- **Memory Efficiency**: Reduced JVM overhead and garbage collection
- **Query Acceleration**: 2-5x performance improvement for analytical queries
- **Compatibility**: Drop-in replacement for Spark SQL execution

## Prerequisites

- ✅ [Infrastructure deployed](/data-on-eks/docs/datastacks/spark-on-eks/infra)
- ✅ Gluten-enabled Spark images available
- ✅ Velox native libraries installed

## Quick Deploy & Test

### 1. Deploy Gluten-Enabled Benchmark

```bash
kubectl apply -f - <<EOF
apiVersion: sparkoperator.k8s.io/v1beta2
kind: SparkApplication
metadata:
  name: gluten-velox-benchmark
  namespace: spark-team-a
spec:
  type: Scala
  mode: cluster
  image: "public.ecr.aws/data-on-eks/spark-gluten:3.5.0"
  mainClass: "com.databricks.spark.sql.perf.tpcds.TPCDS"
  sparkConf:
    "spark.gluten.enabled": "true"
    "spark.gluten.sql.columnar.backend.lib": "velox"
    "spark.sql.adaptive.enabled": "true"
    "spark.plugins": "io.glutenproject.GlutenPlugin"
  driver:
    cores: 4
    memory: "8g"
  executor:
    cores: 8
    instances: 5
    memory: "16g"
EOF
```

### 2. Compare with Standard Spark

```bash
# Run identical workload without Gluten
kubectl apply -f - <<EOF
apiVersion: sparkoperator.k8s.io/v1beta2
kind: SparkApplication
metadata:
  name: standard-spark-benchmark
  namespace: spark-team-a
spec:
  type: Scala
  mode: cluster
  image: "public.ecr.aws/spark/spark:3.5.0"
  mainClass: "com.databricks.spark.sql.perf.tpcds.TPCDS"
  sparkConf:
    "spark.sql.adaptive.enabled": "true"
  driver:
    cores: 4
    memory: "8g"
  executor:
    cores: 8
    instances: 5
    memory: "16g"
EOF
```

## Expected Results

✅ **2-5x Performance**: Significant query acceleration
✅ **Reduced Memory**: Lower JVM memory pressure
✅ **CPU Efficiency**: Better CPU utilization with SIMD
✅ **Compatibility**: Seamless Spark SQL integration

## Related Blueprints

- [Spark Operator Benchmarks](/data-on-eks/docs/datastacks/spark-on-eks/spark-operator-benchmarks)
- [Graviton Benchmarks](/data-on-eks/docs/datastacks/spark-on-eks/graviton-benchmarks)

## Additional Resources

- [Gluten Project](https://github.com/oap-project/gluten)
- [Velox Documentation](https://facebookincubator.github.io/velox/)
