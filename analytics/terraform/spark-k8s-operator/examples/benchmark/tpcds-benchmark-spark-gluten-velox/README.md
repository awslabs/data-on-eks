# TPC-DS Benchmark: Spark vs Gluten+Velox

Performance benchmark comparing Native Apache Spark with Gluten+Velox acceleration using 1TB TPC-DS dataset.

## 🚀 Quick Results

- **Overall Performance**: Gluten+Velox **1.72× faster** than native Spark SQL
- **Query Coverage**: 103/104 queries completed (99% compatibility)
- **Peak Speedup**: Up to **5.48× faster** on aggregation-heavy queries
- **Runtime**: 20.9 min (Gluten) vs 33.5 min (Native)

## 📁 Files

| File | Purpose |
|------|---------|
| `tpcds-benchmark-native-c5d.yaml` | Native Spark benchmark job |
| `tpcds-benchmark-gluten-c5d.yaml` | Gluten+Velox benchmark job |
| `Dockerfile-tpcds-gluten-velox` | Docker image with Gluten+Velox |
| `build-tpcds-gluten-image.sh` | Build script for Gluten image |
| `results/` | Benchmark results and comparison data |

## ⚡ Quick Start

1. **Build Gluten image**:
   ```bash
   ./build-tpcds-gluten-image.sh v1.0.0
   ```

2. **Run benchmarks**:
   ```bash
   export S3_BUCKET=your-bucket-name

   # Native Spark
   envsubst < tpcds-benchmark-native-c5d.yaml | kubectl apply -f -

   # Gluten+Velox
   envsubst < tpcds-benchmark-gluten-c5d.yaml | kubectl apply -f -
   ```

3. **Monitor progress**:
   ```bash
   kubectl get sparkapplications -n spark-team-a
   ```

## 📖 Complete Documentation

For detailed architecture, configuration, and analysis, see:
**[Apache Spark with Gluten+Velox Benchmark Guide](../../../../../../website/docs/benchmarks/spark-operator-benchmark/spark-gluten-velox-benchmark.md)**

## 🔧 Requirements

- **EKS Cluster** with Spark Operator
- **Instance Types**: c5d.12xlarge (8 nodes)
- **Storage**: S3 bucket for data and results
- **Image Registry**: Docker Hub account for custom images
