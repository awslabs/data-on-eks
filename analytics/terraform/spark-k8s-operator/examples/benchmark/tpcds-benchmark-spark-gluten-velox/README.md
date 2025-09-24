# TPC-DS Benchmark: Native Spark vs Gluten+Velox

This folder contains a comprehensive TPC-DS 1TB benchmark comparison between Native Spark and Gluten+Velox on Kubernetes.

## Overview

- **Dataset**: TPC-DS 1TB (99 analytical queries)
- **Infrastructure**: c5d.12xlarge instances with NVMe SSDs
- **Spark Versions**:
  - Native: 3.5.3
  - Gluten: 3.5.2 (Gluten v1.4.0 compatibility)
- **Expected Runtime**: 60-120 minutes per benchmark

## Files

### Benchmark Configurations
- `tpcds-benchmark-native-c5d.yaml` - Native Spark TPC-DS benchmark
- `tpcds-benchmark-gluten-c5d.yaml` - Gluten+Velox TPC-DS benchmark

### Docker Images
- `Dockerfile-tpcds-gluten-velox` - Extends Spark 3.5.2 Gluten base with TPC-DS toolkit

### Scripts
- `build-tpcds-gluten-image.sh` - Build and push Gluten TPC-DS Docker image
- `run-tpcds-comparison.sh` - Deploy and manage both benchmarks

## Quick Start

1. **Build the Gluten TPC-DS image:**
   ```bash
   cd /path/to/tpcds-benchmark-spark-gluten-velox
   ./build-tpcds-gluten-image.sh v1.0.0
   ```

2. **Set environment variables:**
   ```bash
   export S3_BUCKET=$(terraform output -raw s3_bucket_id_spark_history_server)
   ```

3. **Run both benchmarks:**
   ```bash
   ./run-tpcds-comparison.sh both
   ```

4. **Monitor progress:**
   ```bash
   ./run-tpcds-comparison.sh status
   ./run-tpcds-comparison.sh logs
   ```

5. **Clean up when done:**
   ```bash
   ./run-tpcds-comparison.sh cleanup
   ```

## Architecture

### Native Spark Configuration
- **Image**: `public.ecr.aws/data-on-eks/spark3.5.3-scala2.12-java17-python3-ubuntu-tpcds:v2`
- **Executor Config**: 36 executors (6 per node), 5 cores, 20g memory each
- **Optimizations**: AQE, S3A with disk buffering, Prometheus metrics

### Gluten+Velox Configuration
- **Image**: `<dockerhubuser>/spark-tpcds-gluten-velox:v1.0.0`
- **Base**: Spark 3.5.2 + Gluten v1.4.0 + Velox backend
- **Executor Config**: Same as native (36 executors, 5 cores, 20g memory)
- **Optimizations**: Vectorized execution, columnar shuffle, off-heap memory

## Performance Analysis

### Expected Gluten+Velox Advantages
- **Aggregations**: 2-5x faster with vectorized operations
- **Window Functions**: 3-10x speedup with columnar processing
- **Complex Analytics**: Better CPU utilization with SIMD instructions
- **Memory Efficiency**: Reduced garbage collection with off-heap storage

### Monitoring Results
- **Spark History Server**: `kubectl port-forward svc/spark-history-server 18080:80 -n spark-team-a`
- **Event Logs**: `s3://$S3_BUCKET/spark-event-logs/`
- **Results**:
  - Native: `s3://$S3_BUCKET/TPCDS-TEST-1TB-RESULT-NATIVE/`
  - Gluten: `s3://$S3_BUCKET/TPCDS-TEST-1TB-RESULT-GLUTEN/`

## Infrastructure Requirements

### Node Configuration
```yaml
nodeSelector:
  karpenter.sh/capacity-type: "on-demand"
  node.kubernetes.io/instance-type: "c5d.12xlarge"
```

### Instance Specifications
- **c5d.12xlarge**: 48 vCPUs, 96 GiB RAM, 2x900 GiB NVMe SSD
- **Network**: 12 Gbps bandwidth
- **Storage**: `/mnt/k8s-disks/0` for local Spark directories

## Troubleshooting

### Common Issues
- **Node Availability**: Ensure c5d.12xlarge capacity in your region
- **S3 Permissions**: Verify IRSA role has S3 access
- **Memory Errors**: Monitor off-heap usage in Gluten jobs

### Debug Commands
```bash
# Check node availability
kubectl get nodes -l node.kubernetes.io/instance-type=c5d.12xlarge

# Monitor pods
kubectl get pods -n spark-team-a -w

# Check logs
kubectl logs -n spark-team-a -l spark-app-name=tpcds-benchmark-gluten-c5d --tail=100
```

This benchmark provides definitive performance comparison between Native Spark and Gluten+Velox acceleration on realistic analytical workloads.
